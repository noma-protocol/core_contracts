import fs from 'fs';
import path from 'path';
import fetch from 'node-fetch';
import dotenv from 'dotenv';

// Load environment variables from .env
dotenv.config();

const RPC_URL = process.env.RPC_URL;

if (!RPC_URL) {
    console.error('Error: RPC_URL is not defined in the environment variables.');
    process.exit(1);
}

// Get the directory of the current script
const __dirname = path.resolve();

// Fetch network ID dynamically from the provider
async function getNetworkId(rpcUrl) {
    const response = await fetch(rpcUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            jsonrpc: '2.0',
            method: 'net_version',
            params: [],
            id: 1,
        }),
    });

    const data = await response.json();
    if (!data.result) {
        throw new Error('Failed to fetch network ID.');
    }
    return data.result; // Network ID as a string
}

// Function to extract contract addresses
function extractContractAddresses(inputFilePaths, filteredContracts, networkId) {
    let deploymentData = {};

    // Load existing deployment.json if it exists
    const outputFilePath = `${__dirname}/helper_script/out/deployment.json`;
    if (fs.existsSync(outputFilePath)) {
        const existingData = fs.readFileSync(outputFilePath, 'utf-8');
        deploymentData = JSON.parse(existingData);
    }

    // Ensure the network ID exists in the deployment data
    if (!deploymentData[networkId]) {
        deploymentData[networkId] = {};
    }

    // Iterate through input files
    for (const filePath of inputFilePaths) {
        if (!fs.existsSync(filePath)) {
            console.warn(`Warning: File not found: ${filePath}`);
            continue;
        }

        const rawData = fs.readFileSync(filePath, 'utf-8');
        const data = JSON.parse(rawData);

        for (const transaction of data.transactions) {
            const { contractName, contractAddress } = transaction;

            // Append only filtered contracts
            if (filteredContracts.includes(contractName)) {
                if (!deploymentData[networkId][contractName]) {
                    deploymentData[networkId][contractName] = contractAddress;
                } else {
                    console.warn(`Duplicate contractName "${contractName}" found. Skipping.`);
                }
            }
        }
    }

    // Write updated data back to deployment.json
    fs.writeFileSync(outputFilePath, JSON.stringify(deploymentData, null, 2));
    console.log(`Deployment addresses updated in: ${outputFilePath}`);
}

// Main function
(async () => {
    try {
        const networkId = await getNetworkId(RPC_URL);

        console.log(`Fetched network ID: ${networkId}`);

        // Dynamically construct input file paths based on network ID
        const inputFilePaths = [
            path.join(__dirname, `./broadcast/DeployFactory.s.sol/${networkId}/run-latest.json`),
            path.join(__dirname, `./broadcast/DeployVault.s.sol/${networkId}/run-latest.json`),
        ];

        // console.log('Input file paths:', inputFilePaths);

        const filteredContracts = ['VaultUpgrade']; // Add your filtered contracts

        // Extract contract addresses
        extractContractAddresses(inputFilePaths, filteredContracts, networkId);
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
})();
