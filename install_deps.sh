#!/bin/bash

rm -rf cache/ out/ lib/v3-core/ lib/v3-periphery/ lib/openzeppelin-contracts-upgradeable

# Create the lib directory if it doesn't already exist
mkdir -p lib

# Clone repositories only if their folders do not exist
if [ ! -d "lib/v3-periphery" ]; then
    echo "Cloning v3-periphery..."
    git clone --branch main https://github.com/noma-protocol/v3-periphery lib/v3-periphery
else
    echo "v3-periphery already exists. Skipping..."
fi

if [ ! -d "lib/v3-core" ]; then
    echo "Cloning v3-core..."
    git clone --branch main https://github.com/noma-protocol/v3-core lib/v3-core
else
    echo "v3-core already exists. Skipping..."
fi

if [ ! -d "lib/openzeppelin-contracts" ]; then
    echo "Cloning OpenZeppelin Contracts..."
    git clone --branch v5.1.0 https://github.com/OpenZeppelin/openzeppelin-contracts lib/openzeppelin-contracts
else
    echo "openzeppelin-contracts already exists. Skipping..."
fi

if [ ! -d "lib/openzeppelin-contracts-upgradeable" ]; then
    echo "Cloning OpenZeppelin Contracts Upgradeable..."
    git clone --branch release-v5.2 https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable lib/openzeppelin-contracts-upgradeable
else
    echo "openzeppelin-contracts-upgradeable already exists. Skipping..."
fi

if [ ! -d "lib/solmate" ]; then
    echo "Cloning Solmate..."
    git clone --branch main https://github.com/Rari-Capital/solmate lib/solmate
else
    echo "solmate already exists. Skipping..."
fi

if [ ! -d "lib/abdk-libraries-solidity" ]; then
    echo "Cloning ABDK Libraries Solidity..."
    git clone --branch master https://github.com/abdk-consulting/abdk-libraries-solidity lib/abdk-libraries-solidity
else
    echo "abdk-libraries-solidity already exists. Skipping..."
fi

if [ ! -d "lib/forge-std" ]; then
    echo "Cloning Forge Standard Library..."
    git clone --branch master https://github.com/foundry-rs/forge-std lib/forge-std
else
    echo "forge-std already exists. Skipping..."
fi

if [ ! -d "lib/openzeppelin-foundry-upgrades" ]; then
    echo "Cloning foundry-upgrades..."
    git clone --branch main https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades lib/openzeppelin-foundry-upgrades
else
    echo "forge-std already exists. Skipping..."
fi

if [ ! -d "lib/solidity-stringutils" ]; then
    echo "Cloning solidity-stringutils..."
    git clone --branch master https://github.com/Arachnid/solidity-stringutils lib/solidity-stringutils
else
    echo "forge-std already exists. Skipping..."
fi


echo "All repositories have been checked and cloned if necessary!"
