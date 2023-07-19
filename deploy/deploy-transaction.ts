import { utils, Provider, Wallet,Contract,EIP712Signer,types } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { ZKSYNC_MAIN_ABI } from "zksync-web3/build/src/utils";
import deployMultisig from "./deploy-multisig";

export default async function (hre: HardhatRuntimeEnvironment) {
// const provider = new Provider("https://zksync2-testnet.zksync.dev");
const provider = new Provider("http://localhost:3050/");

const wallet = new Wallet("0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110");
const deployer = new Deployer(hre, wallet);

const owner1 = new ethers.Wallet("0xd448c30e6d75d195768346a54a0e27f12d2860d09e6e9f177b861090c29d935e");
const owner2 = new ethers.Wallet("0x958ca55ed5c0c0d42a956103ed1f0bb6bd08b289a9f43fa8c3ac65a301fcd78d");
const accountArtifact = await deployer.loadArtifact("TwoUserMultisig");
//
const erc20Artifact = await deployer.loadArtifact("MyERC20");
//const erc201 = '0xC614909530f3905023E46fe8195B174E971A1ED4';
//const erc20 = new ethers.Contract(erc20Artifact, provider);
//const erc20Contract = await erc20.deploy();
const erc20 = (await deployer.deploy(erc20Artifact, ["localtoken", "TT", 18]));
console.log(`erc: "${erc20.address}",`)
//const paymaster = "0x6c4f87c025020d6d0Aa40414CdcdCbf09bAFaA48";

const accountContract = "0x14c47054cCF3D52Ce7F5540A627950eCFDe0dce7"
console.log(`Minting 5 tokens for empty wallet`);

await (
      await deployer.zkWallet.sendTransaction({
        to: accountContract,
        value: ethers.utils.parseEther("0.3"),
      })       
    ).wait();
   console.log(deployer.zkWallet.address)


// const paymasterParams = utils.getPaymasterParams(paymaster, {
//   type: "ApprovalBased",
//   token: erc201,
//   // set minimalAllowance as we defined in the paymaster contract
//   minimalAllowance: ethers.BigNumber.from(1),
//   // empty bytes as testnet paymaster does not use innerInput
//   innerInput: new Uint8Array(),
// });
// console.log(paymasterParams)

let mint = await erc20.populateTransaction.mint(wallet.address, 5);
// 
 mint = {
  ...mint,
  from: accountContract,
  chainId: (await provider.getNetwork()).chainId,
  nonce: await provider.getTransactionCount(accountContract),
  type: 113,
  customData: {
    gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
   // paymasterParams: paymasterParams,
  } as types.Eip712Meta,
  value: ethers.BigNumber.from(0),
 };
 mint.gasPrice = await provider.getGasPrice();
 mint.gasLimit = ethers.BigNumber.from(20000000);
 const signedTxHash = EIP712Signer.getSignedDigest(mint);
  const signature = ethers.utils.concat([
    // Note, that `signMessage` wouldn't work here, since we don't want
    // the signed hash to be prefixed with `\x19Ethereum Signed Message:\n`
    ethers.utils.joinSignature(owner1._signingKey().signDigest(signedTxHash)),
    ethers.utils.joinSignature(owner2._signingKey().signDigest(signedTxHash)),
  ]);
 mint.customData = {
  ...mint.customData,
  customSignature: signature,
 };
 console.log(mint)
 const sentTx = await provider.sendTransaction(utils.serialize(mint));
 await sentTx.wait();
 console.log("after this")
}

//SWC
// registry: "0x3De9Bc674167743C83961d99F9adDD3426BBfC4D",
// moduleManager: "0xe3B3a4e5DAF220bca8F91e4d23a468E0D1930c94",
// aafactory: "0x8f41f36F2cd2cE0FB57cE61f205E6DA17Ab23282",
// account: "0x52751eab8F7b532cb887A85B7d966680D20E22F8",
// ERC20 address: 0xC614909530f3905023E46fe8195B174E971A1ED4
//Paymaster address: 0x6c4f87c025020d6d0Aa40414CdcdCbf09bAFaA48
//https://goerli.explorer.zksync.io/address/0x52751eab8F7b532cb887A85B7d966680D20E22F8
// Multisig - 1
// Path: custom-aa-tutorial/deploy/deploy-multisig.ts
// Owner 1 address: 0x6520813043c87156551C8dFF0eC827aA0F6F255B
// Owner 1 pk: 0x0d08ab7d3133ece3c08b3c632b72394c063b34a1b5129c44d7ac5ad34222e90f
// Owner 2 address: 0xDeB172067C3FAff9180DE840D08Ba5924EE6e456
// Owner 2 pk: 0x7b06b431fa678c0407be9d43d5fd1922e6f4b225b850b494e30efd4b17f8935f
// Multisig account deployed on address 0x7dFe9ce52Aa24027d6B2493D12D35DE785738CEc
// Sending funds to multisig account
// Multisig account balance is 0
// AA factory address: 0x3291718F15f1B87C7F8Ef0F014F5cB74260Bc239
