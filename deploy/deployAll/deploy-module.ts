import { Wallet, Contract} from 'zksync-web3';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';
import { toBN, GASLIMIT } from "./helper";

// Deploy function
export async function deployModules (
    wallet: Wallet,
    deployer: Deployer,
    ):Promise<any> {

    // Deploy AccountRegistry
    const registryArtifact = await deployer.loadArtifact("AccountRegistry");
    const registry = <Contract>(await deployer.deploy(registryArtifact, []));
    console.log(`registry: "${registry.address}",`)

    // Deploy ModuleManager
    const moduleManagerArtifact = await deployer.loadArtifact("ModuleManager");
    const moduleManager = <Contract>(await deployer.deploy(moduleManagerArtifact, [wallet.address, registry.address]));
    console.log(`moduleManager: "${moduleManager.address}",`)

    const scrArtifact = await deployer.loadArtifact("SocialRecovery");
    const sccontract = (await deployer.deploy(scrArtifact,[moduleManager.address]));
    console.log(`sccontract: "${sccontract.address}",`)

    // ModuleManager: add Module: 
    await (await moduleManager.addModule(sccontract.address, GASLIMIT)).wait();
    const tx =  await moduleManager.getModule([1], GASLIMIT);
    console.log(tx)
    return [sccontract, moduleManager, registry]
}