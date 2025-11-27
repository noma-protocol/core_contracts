import { ethers, JsonRpcProvider, formatUnits } from "ethers";
import dotenv from "dotenv";
import abi from "./abi.js";
import colors from "colors";
const VaultArtifact = await import(`../../../out/BaseVault.sol/BaseVault.json`, { assert: { type: "json" } });
const VaultAbi = VaultArtifact.default.abi;
const VaultAuxArtifact = await import(`../../../out/AuxVault.sol/AuxVault.json`, { assert: { type: "json" } });

dotenv.config();

// Replace with your provider (e.g., Infura, Alchemy, or localhost)
const provider = new JsonRpcProvider(process.env.RPC_URL);
// Replace with your private key
const privateKey = process.env.PRIVATE_KEY_BOT;

// Create a signer
const signer = new ethers.Wallet(privateKey, provider);

const modelHelperAddress = process.env.MODEL_HELPER_ADDRESS;
const poolAddress = process.env.POOL_ADDRESS;
const vaultAddress = process.env.VAULT_ADDRESS;

// Create a contract instance
const modelHelper = new ethers.Contract(modelHelperAddress, abi, provider);
const vault = new ethers.Contract(vaultAddress, abi, signer);
const vaultAux = new ethers.Contract(vaultAddress, VaultAuxArtifact.default.abi, signer);
const BaseVault = new ethers.Contract(vaultAddress, VaultAbi, signer);

// Function to call `getLiquidityRatio`
async function fetchLiquidityRatio() {
  try {
    // Call the getLiquidityRatio function
    const includeStaked = true;
     const ret = await BaseVault.getVaultInfo();
 
    const formattedLiquidityRatio = formatUnits(ret[0], 18);

    console.log("Liquidity Ratio:", formattedLiquidityRatio);

    if (formattedLiquidityRatio < 0.90) {
      console.log(colors.green("Liquidity ratio is below threshold. Shifting..."));
    
      const gasEstimate1 = await vault.shift.estimateGas();
      console.log(`Gas estimate for shift: ${gasEstimate1}`);

      await vault.shift();      
    }
    // if (formattedLiquidityRatio > 1.15) {

    //   const gasEstimate2 = await vault.slide.estimateGas();
    //   console.log(`Gas estimate for slide: ${gasEstimate2}`);

    //   console.log(colors.red("Liquidity ratio is above threshold. Sliding..."));
    //   await vault.slide();
    
    // }

    // console.log(colors.yellow("Restoring liquidity..."));
    // await vaultAux.restoreLiquidityPriv();

} catch (error) {
    // console.log( colors.red("Error: ", error.info.error.message || error.message));
    console.error(colors.red("Error fetching liquidity ratio:", error.message));
  }
}

// Call the function every second
setInterval(fetchLiquidityRatio, 3000);


// WETH9 0x8AD2124c0A48Ad025f870f41B4156e93AC7F15c4
