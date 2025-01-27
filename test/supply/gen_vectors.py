from web3 import Web3

# Connect to the local Ethereum node
web3 = Web3(Web3.HTTPProvider('http://127.0.0.1:8545'))

# ABI and contract address
abi = [
    {
        "inputs": [
            {
                "components": [
                    {"internalType": "uint256", "name": "ethAmount", "type": "uint256"},
                    {"internalType": "uint256", "name": "imv", "type": "uint256"},
                    {"internalType": "uint256", "name": "circulating", "type": "uint256"},
                    {"internalType": "uint256", "name": "totalSupply", "type": "uint256"},
                    {"internalType": "uint256", "name": "volatility", "type": "uint256"},
                    {"internalType": "uint256", "name": "kr", "type": "uint256"},
                    {"internalType": "uint256", "name": "kv", "type": "uint256"}
                ],
                "internalType": "struct RewardCalculator.RewardParams",
                "name": "params",
                "type": "tuple"
            }
        ],
        "name": "calculateRewards",
        "outputs": [
            {"internalType": "uint256", "name": "", "type": "uint256"}
        ],
        "stateMutability": "pure",
        "type": "function"
    }
]
contract_address = '0x5FA1ca15965eE8cD50c9270691dc34bA7bA8bb34'

# Initialize contract
contract = web3.eth.contract(address=contract_address, abi=abi)


# Define RewardParams as a dictionary (tuple equivalent)
reward_params = {
    "ethAmount": Web3.to_wei(10, 'ether'),    # 1 ETH
    "imv": Web3.to_wei(0.05, 'ether'),     # Token price in ETH (e.g., 0.005 ETH)
    "circulating": Web3.to_wei(1, 'ether'),  # Circulating supply
    "totalSupply": Web3.to_wei(5, 'ether'), # Total supply
    "volatility": Web3.to_wei(1, 'ether'),   # 180% as 1.8e18
    "kr": Web3.to_wei(100, 'ether'),            # Sensitivity for r adjustment
    "kv": Web3.to_wei(1, 'ether')              # Sensitivity for volatility adjustment
}

# Call the function
try:
    result = contract.functions.calculateRewards(reward_params).call()
    print("Calculated Rewards:", Web3.from_wei(result, 'ether'))
except Exception as e:
    print("Error:", str(e))
