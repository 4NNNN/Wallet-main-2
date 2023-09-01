// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

/// @title Enum - Collection of enums
abstract contract Enum {
    enum Operation {
        Call,
        DelegateCall
    }
}