// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IAccount.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";

import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
// Used for signature validation
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./Modules/Multicall.sol";
// Access zkSync system contracts, in this case for nonce validation vs NONCE_HOLDER_SYSTEM_CONTRACT
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
// to call non-view method of system contracts
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";
import "./interfaces/IModule.sol";
import "./interfaces/IModuleManager.sol";

contract TwoUserMultisig is IAccount,IERC1271,Multicall {
    // to get transaction hash
    using TransactionHelper for Transaction;
    address public owner;
    address public moduleManager;
    // state variables for account owners
    address public owner1;
    address public owner2;

    bytes4 constant EIP1271_SUCCESS_RETURN_VALUE = 0x1626ba7e;

     /// @dev returns true if the address is an enabled module.
    mapping(address => bool) public isModule;

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this method"
        );
        // Continure execution if called from the bootloader.
        _;
    }

    // @dev modifier to block calls from non-account(address(this)) and non-owner address
    modifier onlySelfOrOwner() {
        require(
            msg.sender == address(this) || msg.sender == owner1 || msg.sender == owner2,
            "ONLY_SELF_OR_OWNER"
        );
        _;
    }

    modifier mixedAuth() {
        if (msg.sender != owner1 && msg.sender != owner2 && msg.sender != address(this))
            revert MixedAuthFail(msg.sender);
        _;
    }
    // event EOAChanged(
    //     address indexed _scw,
    //     address indexed _oldEOA1,
    //     address indexed _newEOA1,
    //     address indexed _oldEOA2,
    //     address indexed _newEOA2
    // );

     error MixedAuthFail(address caller);
     error OwnerCannotBeZero();
     error OwnerCanNotBeSelf();
     error OwnerProvidedIsSame();

    constructor(address _owner1, address _owner2,address _moduleManager) {
        owner1 = _owner1;
        owner2 = _owner2;
        moduleManager = _moduleManager;
    }

    // ---------------------------------- //
    //          Modules Add/Remove        //
    // ---------------------------------- //

    /// @notice this function enables available modules for the account
    /// @dev fetches module addresses by getModule(moduleId) from moduleManager
    /// @param _moduleIds: arrays of module identification numbers.
    function addModules(uint256[] memory _moduleIds) public onlySelfOrOwner {
        for (uint256 i; i < _moduleIds.length; i++) {
            (address module) = IModuleManager(moduleManager)
                .getModule(_moduleIds[i]);

            require(!isModule[module], "MODULE_ENABLED");
            IModule(module).addAccount(address(this));
            isModule[module] = true;
        }
    }

    /// @notice this function disables added modules for the account
    /// @dev fetches module addresses by getModule(moduleId) from moduleManager
    /// @param _moduleIds: arrays of module identification numbers.
    function removeModules(uint256[] memory _moduleIds) public onlySelfOrOwner {
        for (uint256 i; i < _moduleIds.length; i++) {
            (address module) = IModuleManager(moduleManager)
                .getModule(_moduleIds[i]);

            require(isModule[module], "MODULE_NOT_ENABLED");
            IModule(module).removeAccount(address(this));
            isModule[module] = false;
        }
    }

    /**
     * @dev Allows to change the owner of the smart account by current owner or self-call (modules)
     
     */
    function setOwner(address _newOwner1,address _newOwner2) public mixedAuth {
        if (_newOwner1 == address(0)) revert OwnerCannotBeZero();
        if (_newOwner2 == address(0)) revert OwnerCannotBeZero();
        if (_newOwner1 == address(this)) revert OwnerCanNotBeSelf();
        if (_newOwner2 == address(this)) revert OwnerCanNotBeSelf();
        if (_newOwner1 == owner1) revert OwnerProvidedIsSame();
        if (_newOwner2 == owner2) revert OwnerProvidedIsSame();
        address oldOwner1 = owner1;
        address oldOwner2 = owner2;
        assembly {
            sstore(owner1.slot, _newOwner1)
            sstore(owner2.slot, _newOwner2)
        }
        //emit EOAChanged(address(this), oldOwner1, _newOwner1,oldOwner2,_newOwner2);
    }

    function validateTransaction(
        bytes32,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable override onlyBootloader returns (bytes4 magic) {
        magic = _validateTransaction(_suggestedSignedHash, _transaction);
    }

    function _validateTransaction(
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) internal returns (bytes4 magic) {
        // Incrementing the nonce of the account.
        // Note, that reserved[0] by convention is currently equal to the nonce passed in the transaction
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );

        bytes32 txHash;
        // While the suggested signed hash is usually provided, it is generally
        // not recommended to rely on it to be present, since in the future
        // there may be tx types with no suggested signed hash.
        if (_suggestedSignedHash == bytes32(0)) {
            txHash = _transaction.encodeHash();
        } else {
            txHash = _suggestedSignedHash;
        }

        // The fact there is are enough balance for the account
        // should be checked explicitly to prevent user paying for fee for a
        // transaction that wouldn't be included on Ethereum.
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        require(totalRequiredBalance <= address(this).balance, "Not enough balance for fee + value");

        if (isValidSignature(txHash, _transaction.signature) == EIP1271_SUCCESS_RETURN_VALUE) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        }
    }

    function executeTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        _executeTransaction(_transaction);
    }

    function _executeTransaction(Transaction calldata _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());

            // Note, that the deployer contract can only be called
            // with a "systemCall" flag.
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
           
        }
        // else if (isBatched(_transaction.data, to)){
        //      multicall(_transaction.data[4:]);
        // }
        else if (isModule[to]){
            Address.functionDelegateCall(to, data);
        }
        else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            require(success);
        }
    }

    function executeTransactionFromOutside(Transaction calldata _transaction)
        external
        payable
    {
        _validateTransaction(bytes32(0), _transaction);
        _executeTransaction(_transaction);
    }

    function isValidSignature(bytes32 _hash, bytes memory _signature)
        public
        view
        override
        returns (bytes4 magic)
    {
        magic = EIP1271_SUCCESS_RETURN_VALUE;

        if (_signature.length != 130) {
            // Signature is invalid anyway, but we need to proceed with the signature verification as usual
            // in order for the fee estimation to work correctly
            _signature = new bytes(130);
            
            // Making sure that the signatures look like a valid ECDSA signature and are not rejected rightaway
            // while skipping the main verification process.
            _signature[64] = bytes1(uint8(27));
            _signature[129] = bytes1(uint8(27));
        }

        (bytes memory signature1, bytes memory signature2) = extractECDSASignature(_signature);

        if(!checkValidECDSASignatureFormat(signature1) || !checkValidECDSASignatureFormat(signature2)) {
            magic = bytes4(0);
        }

        address recoveredAddr1 = ECDSA.recover(_hash, signature1);
        address recoveredAddr2 = ECDSA.recover(_hash, signature2);

        // Note, that we should abstain from using the require here in order to allow for fee estimation to work
        if(recoveredAddr1 != owner1 || recoveredAddr2 != owner2) {
            magic = bytes4(0);
        }
    }

    // This function verifies that the ECDSA signature is both in correct format and non-malleable
    function checkValidECDSASignatureFormat(bytes memory _signature) internal pure returns (bool) {
        if(_signature.length != 65) {
            return false;
        }

        uint8 v;
		bytes32 r;
		bytes32 s;
		// Signature loading code
		// we jump 32 (0x20) as the first slot of bytes contains the length
		// we jump 65 (0x41) per signature
		// for v we load 32 bytes ending with v (the first 31 come from s) then apply a mask
		assembly {
			r := mload(add(_signature, 0x20))
			s := mload(add(_signature, 0x40))
			v := and(mload(add(_signature, 0x41)), 0xff)
		}
		if(v != 27 && v != 28) {
            return false;
        }

		// EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if(uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return false;
        }

        return true;
    }
    
    function extractECDSASignature(bytes memory _fullSignature) internal pure returns (bytes memory signature1, bytes memory signature2) {
        require(_fullSignature.length == 130, "Invalid length");

        signature1 = new bytes(65);
        signature2 = new bytes(65);

        // Copying the first signature. Note, that we need an offset of 0x20 
        // since it is where the length of the `_fullSignature` is stored
        assembly {
            let r := mload(add(_fullSignature, 0x20))
			let s := mload(add(_fullSignature, 0x40))
			let v := and(mload(add(_fullSignature, 0x41)), 0xff)

            mstore(add(signature1, 0x20), r)
            mstore(add(signature1, 0x40), s)
            mstore8(add(signature1, 0x60), v)
        }

        // Copying the second signature.
        assembly {
            let r := mload(add(_fullSignature, 0x61))
            let s := mload(add(_fullSignature, 0x81))
            let v := and(mload(add(_fullSignature, 0x82)), 0xff)

            mstore(add(signature2, 0x20), r)
            mstore(add(signature2, 0x40), s)
            mstore8(add(signature2, 0x60), v)
        }
    }

    function payForTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        bool success = _transaction.payToTheBootloader();
        require(success, "Failed to pay the fee to the operator");
    }

    function prepareForPaymaster(
        bytes32, // _txHash
        bytes32, // _suggestedSignedHash
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        _transaction.processPaymasterInput();
    }

    /// @notice method to prove that this contract inherits IAccount interface, called
    /// @param interfaceId identifier unique to each interface
    /// @return true if this contract implements the interface defined by `interfaceId`
    /// Details: https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
    /// This function call must use less than 30 000 gas
    function supportsInterface(bytes4 interfaceId)
        external
        pure
        returns (bool)
    {
        return interfaceId == type(IAccount).interfaceId;
    }

    fallback() external {
        // fallback of default account shouldn't be called by bootloader under no circumstances
        assert(msg.sender != BOOTLOADER_FORMAL_ADDRESS);

        // If the contract is called directly, behave like an EOA
    }

    receive() external payable {
        // If the contract is called directly, behave like an EOA.
        // Note, that is okay if the bootloader sends funds with no calldata as it may be used for refunds/operator payments
    }
}
