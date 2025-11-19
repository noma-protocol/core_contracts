// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { VaultStorage } from "../libraries/LibAppStorage.sol";
import { 
    LoanPosition, 
    OutstandingLoan, 
    LiquidityPosition, 
    LiquidityType, 
    ProtocolAddresses, 
    LiquidityInternalPars,
    AmountsToMint
} from "../types/Types.sol";
import { Utils } from "../libraries/Utils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "../interfaces/IVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ITokenRepo } from "../TokenRepo.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol"; 
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import "../libraries/TickMathExtra.sol";
import { IModelHelper } from "../interfaces/IModelHelper.sol";
import { LiquidityDeployer } from "../libraries/LiquidityDeployer.sol";
import { Conversions } from "../libraries/Conversions.sol";
import { Uniswap } from "../libraries/Uniswap.sol";
import { LiquidityOps } from "../libraries/LiquidityOps.sol";
import { IDeployer } from "../interfaces/IDeployer.sol";

error NotAuthorized();
error OnlyInternalCalls();
error NotInitialized();
error LiquidityOpRequired();

interface ILendingVault {
    function loanLTV(address who) external view returns (uint256 ltv1e18);
    function paybackLoan(address who, uint256 amount, bool isSelfRepaying) external;
}

interface INomaFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

/**
 * @title AuxVault
 * @notice A contract for vault auxiliary public functions.
 * @dev n/a.
 */
contract LendingOpsVault {
    using SafeERC20 for IERC20;

    VaultStorage internal _v;

    /**
    * @notice Compute a pro-rata allocation of repayment funds across a set of loans.
    * @param funds            Total amount of debt token to distribute (units of token1).
    * @param pool             Array of eligible loans with their `who` and `borrowAmount`.
    * @param totalOutstanding Sum of all `borrowAmount` values in `pool`. Must be > 0.
    * @return toRepay         Array of per-loan repayment amounts aligned with `pool`.
    * @return spent           Total amount allocated (<= funds).
    */
    function _proRataAllocate(
        uint256 funds,
        OutstandingLoan[] memory pool,
        uint256 totalOutstanding
    ) internal pure returns (uint256[] memory toRepay, uint256 spent) {
        uint256 n = pool.length;
        toRepay = new uint256[](n);
        uint256 remaining = funds;

        // base pro-rata pass
        for (uint256 i = 0; i < n; i++) {
            if (remaining == 0) break;
            uint256 share = Math.mulDiv(funds, pool[i].borrowAmount, totalOutstanding);
            if (share > pool[i].borrowAmount) share = pool[i].borrowAmount;
            if (share > remaining) share = remaining;
            toRepay[i] = share;
            remaining -= share;
        }

        // distribute rounding leftovers
        for (uint256 i = 0; i < n && remaining > 0; i++) {
            uint256 room = pool[i].borrowAmount > toRepay[i] ? (pool[i].borrowAmount - toRepay[i]) : 0;
            if (room == 0) continue;
            uint256 add = room < remaining ? room : remaining;
            toRepay[i] += add;
            remaining -= add;
        }

        spent = funds - remaining;
    }

    /**
    * @notice Repay a window of loans (by LTV) using funds already held by the vault.
    * @param fundsToPull Amount of token1 to allocate across qualifying loans (must be <= vault balance).
    * @param start       Start index (inclusive) into `_v.loanAddresses`; may be 0.
    * @param limit       Max number of addresses to scan from `start`. If 0, scans until the end.
    * @return eligibleCount Number of qualifying loans found in the scanned window.
    * @return totalRepaid   Total token1 actually repaid across the window.
    * @return nextIndex     The index where scanning ended (`end`), for convenient batching.
    */
    function vaultSelfRepayLoans(
        uint256 fundsToPull,
        uint256 start,
        uint256 limit
    )
        public
        onlyInternalCalls
        returns (uint256 eligibleCount, uint256 totalRepaid, uint256 nextIndex)
    {
        address token1 = _v.pool.token1();
        uint256 availableFunds = IERC20(token1).balanceOf(address(this));
        if (fundsToPull == 0 || availableFunds < fundsToPull) {
            return (0, 0, start);
        }

        uint256 n = _v.loanAddresses.length;
        if (n == 0 || start >= n) {
            return (0, 0, start);
        }

        uint256 end = (limit == 0) ? n : start + limit;
        if (end > n) end = n;

        uint256 LTV_THRESHOLD_1E18 = _v.protocolParameters.selfRepayLtvTreshold * 1e15;

        // PASS 1: count
        uint256 count = 0;
        for (uint256 i = start; i < end; i++) {
            if (ILendingVault(address(this)).loanLTV(_v.loanAddresses[i]) >= LTV_THRESHOLD_1E18) {
                unchecked { count++; }
            }
        }
        if (count == 0) {
            return (0, 0, end);
        }

        // PASS 2: build pool
        OutstandingLoan[] memory pool = new OutstandingLoan[](count);
        uint256 totalOutstanding = 0;
        {
            uint256 idx = 0;
            for (uint256 i = start; i < end; i++) {
                address who = _v.loanAddresses[i];
                if (ILendingVault(address(this)).loanLTV(who) >= LTV_THRESHOLD_1E18) {
                    LoanPosition memory loan = _v.loanPositions[who];
                    if (loan.borrowAmount > 0) {
                        pool[idx] = OutstandingLoan({ who: who, borrowAmount: loan.borrowAmount });
                        totalOutstanding += loan.borrowAmount;
                        unchecked { idx++; }
                        if (idx == count) break;
                    }
                }
            }
            if (totalOutstanding == 0) {
                return (0, 0, end);
            }
        }

        // PRO-RATA via helper (reduces locals here)
        (uint256[] memory toRepay, /*spent*/) =
            _proRataAllocate(fundsToPull, pool, totalOutstanding);

        // Apply repayments
        for (uint256 i = 0; i < pool.length; i++) {
            uint256 amt = toRepay[i];
            if (amt == 0) continue;
            ILendingVault(address(this)).paybackLoan(pool[i].who, amt, true);
            totalRepaid += amt;
        }

        nextIndex = end;
        return (count, totalRepaid, nextIndex);
    }

    function bumpFloor(uint256 ethAmount) public onlyManagerOrMultiSig {
        if (!_v.initialized) revert NotInitialized();

        uint256 currentLiquidityRatio = IModelHelper(_v.modelHelper)
        .getLiquidityRatio(address(_v.pool), address(this));

        if (currentLiquidityRatio < 95e16 || currentLiquidityRatio > 105e16) {
            revert LiquidityOpRequired();
        }

        LiquidityPosition[3] memory positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];

        (,,uint256 floorToken0Balance, uint256 floorToken1Balance) = 
        IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(
            address(_v.pool), 
            address(this), 
            LiquidityType.Floor
        );

        (,,, uint256 anchorToken1Balance) = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(
            address(_v.pool), 
            address(this), 
            LiquidityType.Anchor
        );

        (,, uint256 discoveryToken0Balance, ) = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(
            address(_v.pool), 
            address(this), 
            LiquidityType.Discovery
        );

        Uniswap.collect(
            address(_v.pool),
            address(this), 
            positions[0].lowerTick, 
            positions[0].upperTick
        );

        // Collect anchor liquidity
        Uniswap.collect(
            address(_v.pool),
            address(this), 
            positions[1].lowerTick, 
            positions[1].upperTick
        );

        // Collect discovery liquidity
        Uniswap.collect(
            address(_v.pool),
            address(this), 
            positions[2].lowerTick, 
            positions[2].upperTick
        );
        
        uint256 circulatingSupply = IModelHelper(_v.modelHelper)
        .getCirculatingSupply(address(_v.pool), address(this));

        uint256 newFloorPrice = LiquidityDeployer
        .computeNewFloorPrice(
            ethAmount, 
            floorToken1Balance,
            circulatingSupply,
            positions
        );

        int24 newFloorLowerTick = Conversions.priceToTick(
            int256(newFloorPrice),
            _v.tickSpacing,
            IERC20Metadata(_v.pool.token0()).decimals()
        );

        newFloorLowerTick = TickMathExtra.ceilToSpacing(newFloorLowerTick, _v.tickSpacing);

        positions[0].lowerTick = newFloorLowerTick;
        positions[0].upperTick = newFloorLowerTick + _v.tickSpacing;
        
        LiquidityPosition memory newFloorPos = LiquidityDeployer
        .reDeployFloor(
            address(_v.pool), 
            address(this), 
            floorToken0Balance, 
            floorToken1Balance + ethAmount, 
            positions
        );     

        LiquidityPosition memory newAnchorPosition = 
        _redeployAnchor(
            positions,
            ethAmount,
            anchorToken1Balance,
            true
        );

        LiquidityPosition memory newDiscoveryPosition = 
        _redeployDiscovery(
            positions, 
            discoveryToken0Balance
        );

        positions = [
            newFloorPos, 
            newAnchorPosition, 
            newDiscoveryPosition
        ];

        _updatePositions(positions);
        IModelHelper(_v.modelHelper).enforceSolvencyInvariant(address(this));
    }

    function _redeployAnchor(
        LiquidityPosition[3] memory positions,
        uint256 ethAmount,
        uint256 anchorToken1Balance,
        bool isShift
    ) internal returns (LiquidityPosition memory newAnchorPosition) {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(_v.pool).slot0();

        // Deploy new anchor position
        newAnchorPosition = LiquidityOps
        .reDeploy(
            ProtocolAddresses({
                pool: address(_v.pool),
                modelHelper: _v.modelHelper,
                vault: address(this),
                deployer: _v.deployerContract,
                presaleContract: _v.presaleContract,
                adaptiveSupplyController: _v.adaptiveSupplyController
            }),
            LiquidityInternalPars({
                lowerTick: positions[0].upperTick,
                upperTick: Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    IVault(address(this))
                    .getProtocolParameters().shiftAnchorUpperBips,
                    IERC20Metadata(
                        IUniswapV3Pool(_v.pool).token1()
                    ).decimals(),
                    positions[0].tickSpacing
                ),
                amount1ToDeploy: anchorToken1Balance - ethAmount,
                liquidityType: LiquidityType.Anchor
            }),
            isShift
        );
    }

    function _redeployDiscovery(
        LiquidityPosition[3] memory positions,
        uint256 discoveryToken0Balance
    ) internal returns (LiquidityPosition memory newDiscoveryPosition) {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(_v.pool).slot0();

        newDiscoveryPosition = IDeployer(_v.deployerContract)
        .deployPosition(
            address(_v.pool), 
            address(this), 
            positions[1].upperTick,
            Utils.addBipsToTick(
                TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                IVault(address(this)).getProtocolParameters()
                .discoveryBips,
                IERC20Metadata(address(IUniswapV3Pool(_v.pool).token0())).decimals(),
                positions[0].tickSpacing
            ),
            LiquidityType.Discovery, 
            AmountsToMint({
                amount0: discoveryToken0Balance,
                amount1: 0
            })
        ); 
    }

    /**
     * @notice Internal function to update the liquidity positions.
     * @param _positions The new liquidity positions.
     */
    function _updatePositions(LiquidityPosition[3] memory _positions) internal {   
        _v.floorPosition = _positions[0];
        _v.anchorPosition = _positions[1];
        _v.discoveryPosition = _positions[2];
    }
    
    
    /**
     * @notice Modifier to restrict access to internal calls.
     */
    modifier onlyInternalCalls() {
        if (msg.sender != _v.factory && msg.sender != address(this)) revert OnlyInternalCalls();
        _;        
    }

    modifier onlyManagerOrMultiSig() {
        address multiSig = INomaFactory(_v.factory).teamMultiSig();
        if (msg.sender != _v.manager && msg.sender != multiSig) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256(bytes("vaultSelfRepayLoans(uint256,uint256,uint256)")));
        selectors[1] = bytes4(keccak256(bytes("bumpFloor(uint256)")));
        return selectors;
    }
}        
