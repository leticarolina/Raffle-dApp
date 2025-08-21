//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/TokenToFundVRF.sol";
import {CreateSubscription} from "./Interactions.s.sol";

abstract contract CodeConstants {
    // VRF Mock values
    uint96 public MOCK_BASE_FEE = 0;
    uint96 public MOCK_GAS_PRICE = 1 gwei;
    int256 public MOCK_WEI_PER_UNIT_LINK = 1e18;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 keyHash;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address token; // Optional, can be used for native token payments
        uint256 account;
        bool useNativePayment; // if true, uses native payment for VRF requests
    }

    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;
    //this mapping stores a struct NetworkConfig for each chain ID.
    // It allows you to access the network configuration for a specific chain ID.
    //networkConfigs[chainId] = will return the NetworkConfig struct stored for that chain ID.
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function setConfig(
        uint256 chainId,
        NetworkConfig memory networkConfig
    ) public {
        networkConfigs[chainId] = networkConfig;
    }

    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.001 ether, // 0.001 ETH
                interval: 120, //  2 minutes
                vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B, //this value is the address of the VRFCoordinatorV2Plus contract on Sepolia
                keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, //this is the keyhash aka gas lane for Sepolia
                callbackGasLimit: 100_000,
                subscriptionId: 83748736775644622086624080657261491749307570282061869166533472615217857914701, //59348555989737605849604285057428249510813332769843048132307428824801730465258, // Subscription ID for Sepolia, provided by Chainlink
                token: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // Sepolia ETH token address,
                account: vm.envUint("SEPOLIA_PK"), // Optional, can be used for native token payments,
                useNativePayment: true // Use native payment for VRF requests
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // If the local chain ID is already configured, return it.
        //this means if the local chain ID is already set in the mapping, return the existing config.
        if (networkConfigs[LOCAL_CHAIN_ID].vrfCoordinator != address(0)) {
            return networkConfigs[LOCAL_CHAIN_ID];
        }

        // If not, create a new mock VRFCoordinator and return the config.
        vm.startBroadcast(DEFAULT_ANVIL_PRIVATE_KEY);
        VRFCoordinatorV2_5Mock vrfCoordinatorMock = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE,
            MOCK_WEI_PER_UNIT_LINK
        );

        LinkToken linkToken = new LinkToken();

        uint256 subscriptionId = vrfCoordinatorMock.createSubscription();

        vm.stopBroadcast();

        NetworkConfig memory localConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30,
            vrfCoordinator: address(vrfCoordinatorMock),
            keyHash: 0x0, // gas lane doesn't matter for local tests
            callbackGasLimit: 500000,
            subscriptionId: subscriptionId, // use the created subscription ID
            token: address(linkToken), // Link token address for local tests
            account: DEFAULT_ANVIL_PRIVATE_KEY, // Default sender address for local tests provided by Foundry
            useNativePayment: false // Use LINK token for VRF requests in local tests
        });

        networkConfigs[LOCAL_CHAIN_ID] = localConfig;
        return localConfig;
    }
}
