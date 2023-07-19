// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";
import "./interfaces/IAccountRegistry.sol";
contract AAFactory {
    bytes32 public aaBytecodeHash;
    address public moduleManager;
    address public accountRegistry;

    constructor(bytes32 _aaBytecodeHash,address _moduleManager,address _accountRegistry) {
        aaBytecodeHash = _aaBytecodeHash;
        moduleManager = _moduleManager;
        accountRegistry = _accountRegistry;
    }

    function deployAccount(
        bytes32 salt,
        address owner1,
        address owner2
    ) external returns (address accountAddress) {
        (bool success, bytes memory returnData) = SystemContractsCaller
            .systemCallWithReturndata(
                uint32(gasleft()),
                address(DEPLOYER_SYSTEM_CONTRACT),
                uint128(0),
                abi.encodeCall(
                    DEPLOYER_SYSTEM_CONTRACT.create2Account,
                    (salt, aaBytecodeHash, abi.encode(owner1, owner2, moduleManager), IContractDeployer.AccountAbstractionVersion.Version1)
                )
            );
        require(success, "Deployment failed");

        (accountAddress) = abi.decode(returnData, (address));
        IAccountRegistry(accountRegistry)._storeAccount(accountAddress);
    }
}
