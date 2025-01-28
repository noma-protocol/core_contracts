## Noma Protocol core contracts

This is the Noma protocol core contracts repository. Noma is a next-generation DeFi protocol. Read more on our official [website](https://noma.money). 

## Setup for development

To install all dependencies and build the contracts run the following commands:

```console
foo@bar:~$ ./install_deps.sh
```

## Local testing

1) Use anvil to fork the Arbitrum mainnet, replace the fork-url with your rpc node. Do not forget the mnemonic phrase.

```console
foo@bar:~$ anvil --balance 10000000000 --fork-url https://arb-mainnet.g.alchemy.com/v2/DeadBeefDeadBeefDeadBeef --accounts 2 -m "example some key phrase generated randomly you wish to use  goes here" --chain-id=1337 --port 8545
```

Example output:

``` 
Available Accounts
==================

(0) 0x8Fc4f07BCB9396722404bFfBE1A77cF73Af06E47 (10000000000.000000000000000000 ETH)
(1) 0xEbA88149813BEc1cCcccFDb0daCEFaaa5DE94cB1 (10000000000.000000000000000000 ETH)

Private Keys
==================

(0) 0x9998817771311c1cCdddFDb0daCEFaaa5DE94cB1a4d4141333d36adddd01dfff
(1) 0x9f7365f2EFaaa5DE913070x8Fc4f07BCB9396722404bFfBE1A77cF73Af06E47f

```

2) Setup an .env file with DEPLOYER as the first address (0) and the corresponding private key, as well as the local RPC_URL. 

```
 DEPLOYER="0x8Fc4f07BCB9396722404bFfBE1A77cF73Af06E47"
 PRIVATE_KEY="0x9998817771311c1cCdddFDb0daCEFaaa5DE94cB1a4d4141333d36adddd01dfff"
 RPC_URL="http://localhost:8545"
```

3) Deploy contracts with the following command:

```console
foo@bar:~$ ./deploy.sh 
```

4) Run tests with the following command:

```console
foo@bar:~$ forge test --rpc-url http://localhost:8545
``` 

