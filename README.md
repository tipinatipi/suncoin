# SunCoin Installation Script
Shell script to install a [SunCoin Masternode](http://suncoin-network.com/) on a Linux server running Ubuntu 16.04. Use it on your own risk.
***

## Desktop wallet setup  

1. Open the Desktop Wallet.
2. Go to Debug console and generate a private key by typing *masternode genkey*
3. Create a new receiving address and set label to **MN1**
4. Click on Copy address.
5. Send **10000** SUN to **MN1**. You need to send all 10000 coins in one single transaction. Wait for 15 confirmations.
6. Go back to Debug console and type *masternode outputs* to retrieve transaction id and output id.
6. Go to Tools -> Open Masternode Configuration File to edit file:
* Masternodename - MN1
* IP:port - VPS_IP:10332 (default port)
* masternodeprivkey - You got in step 2.
* collateral_output_txid - first part of *masternode outputs*
* collateral_output_index — second part of *masternode outputs* (usually 1 or 0)

## Linux VPS Installation
```
wget -q https://raw.githubusercontent.com/tipinatipi/suncoin/master/suncoin_install.sh
bash suncoin_install.sh
```

## Usage:
```
suncoin-cli masternode status  
suncoin-cli getinfo
```
Also, if you want to check/start/stop **SunCoin**, run one of the following commands as **root**:

```
systemctl status SunCoin.service #To check if SunCoin service is running  
systemctl start SunCoin.service #To start SunCoin service  
systemctl stop SunCoin.service #To stop SunCoin service  
systemctl is-enabled SunCoin.service #To check if SunCoin service is enabled on boot  
```  
***

## Donations

Any donation is highly appreciated

**SUN**: SNGrTaGbVc6HWeWZWZnUgsizQRn7AXaMxd  
**BTC**: 1oEsh52V117HVo7owNqdfERSqposiJsVb  
**ETH**: 0x1881C8bdab137f80a609E9a577F44B3ecbE3A1A5
