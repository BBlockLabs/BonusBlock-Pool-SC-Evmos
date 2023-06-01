# Reward Pool distribution Smart Contract

This is [BonusBlock](https://www.bonusblock.io) reward pool distribution smart contract for the [Evmos Network](https://evmos.org)

Java-way of deployment via org.web3j:core:4.9.8 using Maven build org.web3j:web3j-maven-plugin:4.9.8 plugin:


```
Web3j web3j = Web3j.build(new HttpService("https://eth.bd.evmos.dev:8545"));
Credentials cr = Credentials.create(<string_private_key>);
String adr = cr.getAddress();
long chainId = 9000;
FastRawTransactionManager txMananger = new FastRawTransactionManager(web3j, cr, chainId);

// Ensure that the model is already built for the <soliditySourceFiles/> web3j-maven-plugin
org.web3j.model.PoolTokenContract contract = PoolTokenContract.deploy(web3j,txManangernew DefaultGasProvider(), adr)
    .send();
```

