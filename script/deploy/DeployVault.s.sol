// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { NomaFactory } from  "../../src/factory/NomaFactory.sol";
import { 
    ProtocolAddresses,
    VaultDeployParams, 
    PresaleUserParams, 
    VaultDescription, 
    ProtocolParameters 
} from "../../src/types/Types.sol";
import { IDOHelper } from "../../test/IDO_Helper/IDOHelper.sol";
import { BaseVault } from  "../../src/vault/BaseVault.sol";
import { Migration } from "../../src/bootstrap/Migration.sol";
struct ContractAddressesJson {
    address Factory;
    address ModelHelper;
}

interface IPresaleContract {
    function setMigrationContract(address _migrationContract) external ;

}

contract DeployVault is Script {
    using stdJson for string;

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WMON = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address private oikosFactoryAddress;
    address private modelHelper;

    IDOHelper private idoManager;

    function run() public {  
        vm.startBroadcast(privateKey);

        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);
        string memory networkId = "1337"; //"10143"; 

        // Parse the data for network ID `1337`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Model Helper Address:", addresses.ModelHelper);
        console2.log("Factory Address:", addresses.Factory);

        // Extract addresses from JSON
        modelHelper = addresses.ModelHelper;
        oikosFactoryAddress = addresses.Factory;

        NomaFactory oikosFactory = NomaFactory(oikosFactoryAddress);

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "NOMA TOKEN",
            "NOMA",
            18,
            14000000000000000000000000,
            1400000000000000000000000000,
            10000000000000,
            0,
            WMON,
            3000,
            0 // 0 = no presale
        );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            27000000000000000000, // softCap
            900 //2592000          // duration (seconds)
        );

        (address vault, address pool, address proxy) = 
        oikosFactory
        .deployVault(
            presaleParams,
            vaultDeployParams
        );

        BaseVault vaultContract = BaseVault(vault);
        ProtocolAddresses memory protocolAddresses = vaultContract.getProtocolAddresses();

        // uint256[22] memory balances = [
        //     uint256(821855660000000000000000), // ← cast to uint256
        //     uint256(1000 ether), // test
        //     uint256(142125177948252730000000),
        //     uint256(141819746666666670000000),
        //     uint256(82179872374420900000000),
        //     uint256(56071302376270556000000),
        //     uint256(55014554684083880000000),
        //     uint256(29595706717098175000000),
        //     uint256(23831250433535777000000),
        //     uint256(22912761022461866000000),
        //     uint256(22205249692559817000000),
        //     uint256(25729855914365740000000),
        //     uint256(20680476365648523000000),
        //     uint256(17779055436470426000000),
        //     uint256(16590966209666483000000),
        //     uint256(13475628506355670000000),
        //     uint256(13435536658859444000000),
        //     uint256(6777943664458985000000),
        //     uint256(5559888797871999000000),
        //     uint256(4767159737846081000000),
        //     uint256(1395762173337634000000),
        //     uint256(19159389245676060000)
        // ];

        // Migration migration = new Migration(
        //     modelHelper,
        //     proxy,
        //     vault,
        //     37850000000000, // initialIMV
        //     7776000, // duration (90 days)
        //     [
        //         0xd8a9A164E361BC9aaC64e2373151120Ad447961a, // Grupo Moris
        //         0xd28Be47a16c41Ff1e0DAd01197A7A0970bb9EeC1, // test
        //         0x7a81d1831Eae6bCaC75F55562325ceB709D9eEAD,
        //         0x4334Be7D449A6FB3488C1CC3e940597c70609068,
        //         0xf86Fff60ACe8AB04340f4518B1c40349396ddF5F,
        //         0xcefE57a6D77D24c75B1ba883d8bCAf62D8dd38B6,
        //         0x72A989edF79125E7eA4Eb38826f14e9E6D0Ced4d,
        //         0xE87C4168b50f1307ecA7F28684a7C3Ed37163420,
        //         0xf79cD7b73c86cf051D6E814c4E457081e019F85e,
        //         0x4ca5d9382096096E40f243F1E7dDe151d6ea9497,
        //         0x33b9583Ed51e305bB053E1795c0FcFf7a8A68379, // Adri
        //         0xFeb74115aC8a866cBDc0df5e50B6F312Fe496ea5,
        //         0x02Ad56758feF56099Cf57531D0C97Bb1Aa1F076e,
        //         0x11bB16aADDA2170475210Af3aAB2188C0F74b11B,
        //         0x5b1804ac4e1835357EAfD95c55CD3e730224C4a2,
        //         0xd7b39eEB1b38F1b56fd0c635019f397524b57fda,
        //         0x5c4f2619fAD8d51CA0986c9f6f3Ebe348f31A0F8,
        //         0x308e6842FF0Afe084fC80eEE6d7DfF65813C8F64,
        //         0xf142B41e009c65370Cf1810027AC585ED3ff09ae,
        //         0xfa8a0F2Bcc5Fb457cdC0CB94d5495671aafD99Fe,
        //         0x07b5AC17cEa37b8B9e6b9a59682c5774D9196875,
        //         0x816E9359Ea847839e0bE4C18218e6658a1Ac3662
        //     ],
        //     balances
        // );

        // console.log("Presale contract address: ", protocolAddresses.presaleContract);

        // IPresaleContract(protocolAddresses.presaleContract).setMigrationContract(address(migration));
        idoManager = new IDOHelper(pool, vault, modelHelper, proxy, WMON);

        console.log("Vault address: ", vault);
        console.log("Pool address: ", pool);
        console.log("Proxy address: ", proxy);
        console.log("IDOHelper address: ", address(idoManager));
    }
}