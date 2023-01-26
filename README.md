

### Conductive Finance 

Conductive Finance aims to rebase value investment on the dynamics of purpose by leveraging accessible, trustworthy and consciously imparted ledgers in predictable, standardized and understandable ways.

See [discourse.md](https://github.com/parseb/conductive.finance1/blob/main/discourse.md) for genesis story and high-level description.

___

##### Requirements
Brownie
`pip3 install eth-brownie`

You will also need to set up RPC endpoint API key and Blockexplorer Key as the development so far has amde extensive use of forking and pulling contract code from etherscan/polygonscan.

add the following values to ~/.bashrc

export ETHERSCAN_TOKEN= (optional)
export WEB3_INFURA_PROJECT_ID= (infura endpoint id)
export POLYGONSCAN_TOKEN= (requires polygonscan account)

##### run tests

`brownie test --network polygon-main-fork -I -s`
____
open issue if issue
