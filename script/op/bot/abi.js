const abi = [
    {
        "inputs": [
            { "internalType": "address", "name": "pool", "type": "address" },
            { "internalType": "address", "name": "vault", "type": "address" }
        ],
        "name": "getLiquidityRatio",
        "outputs": [
            { "internalType": "uint256", "name": "liquidityRatio", "type": "uint256" }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "shift",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "slide",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
];

export default abi;
