use contract::base::types::{Category, Pool, PoolDetails, Status};
use contract::interfaces::ierc721::{
    IERC721Mintable, IERC721MintableDispatcher, IERC721MintableDispatcherTrait,
};
use contract::interfaces::ipredifi::{IPredifiDispatcher, IPredifiDispatcherTrait};
use core::felt252;
use core::traits::Into;
use openzeppelin::token::erc721::ERC721Component;
use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{
    ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
};


fn owner() -> ContractAddress {
    'owner'.try_into().unwrap()
}

fn deploy_predifi() -> IPredifiDispatcher {
    // First deploy the ERC721 contract
    let deployer: ContractAddress = get_contract_address();
    let (_, erc721_general_dispatch, nft_contract) = deploy_erc721(deployer);

    // Then deploy Predifi with the NFT contract address
    let contract_class = declare("Predifi").unwrap().contract_class();
    let mut constructor_calldata = array![];
    constructor_calldata.append(nft_contract.contract_address.into());
    let (contract_address, _) = contract_class.deploy(@constructor_calldata).unwrap();

    IPredifiDispatcher { contract_address }
}


fn deploy_erc721(
    deployer: ContractAddress,
) -> (ContractAddress, IERC721Dispatcher, IERC721MintableDispatcher) {
    // Declaring the contract class
    let contract_class = declare("ERC721").unwrap().contract_class();
    // Creating the data to send to the constructor, first specifying as a default value
    let mut data_to_constructor = Default::default();
    // Packing the data into the constructor
    Serde::serialize(@deployer, ref data_to_constructor);
    // Deploying the contract, and getting the address
    let (address, _) = contract_class.deploy(@data_to_constructor).unwrap();

    // Returning the address of the contract and the dispatchers
    return (
        address,
        IERC721Dispatcher { contract_address: address },
        IERC721MintableDispatcher { contract_address: address },
    );
}

const ONE_STRK: u256 = 1_000_000_000_000_000_000;

#[test]
fn test_create_pool() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );

    assert!(pool_id != 0, "not created");
}

#[test]
#[should_panic(expected: "Start time must be before lock time")]
fn test_invalid_time_sequence_start_after_lock() {
    let contract = deploy_predifi();
    let (
        poolName,
        poolType,
        poolDescription,
        poolImage,
        poolEventSourceUrl,
        _,
        _,
        poolEndTime,
        option1,
        option2,
        minBetAmount,
        maxBetAmount,
        creatorFee,
        isPrivate,
        category,
    ) =
        get_default_pool_params();

    let current_time = get_block_timestamp();
    let invalid_start_time = current_time + 3600; // 1 hour from now
    let invalid_lock_time = current_time
        + 1800; // 30 minutes from now (before start), should not be able to lock before starting

    contract
        .create_pool(
            poolName,
            poolType,
            poolDescription,
            poolImage,
            poolEventSourceUrl,
            invalid_start_time,
            invalid_lock_time,
            poolEndTime,
            option1,
            option2,
            minBetAmount,
            maxBetAmount,
            creatorFee,
            isPrivate,
            category,
        );
}

#[test]
#[should_panic(expected: "Minimum bet must be greater than 0")]
fn test_zero_min_bet() {
    let contract = deploy_predifi();
    let (
        poolName,
        poolType,
        poolDescription,
        poolImage,
        poolEventSourceUrl,
        poolStartTime,
        poolLockTime,
        poolEndTime,
        option1,
        option2,
        _,
        maxBetAmount,
        creatorFee,
        isPrivate,
        category,
    ) =
        get_default_pool_params();

    contract
        .create_pool(
            poolName,
            poolType,
            poolDescription,
            poolImage,
            poolEventSourceUrl,
            poolStartTime,
            poolLockTime,
            poolEndTime,
            option1,
            option2,
            0,
            maxBetAmount,
            creatorFee,
            isPrivate,
            category,
        );
}

#[test]
#[should_panic(expected: "Creator fee cannot exceed 5%")]
fn test_excessive_creator_fee() {
    let contract = deploy_predifi();
    let (
        poolName,
        poolType,
        poolDescription,
        poolImage,
        poolEventSourceUrl,
        poolStartTime,
        poolLockTime,
        poolEndTime,
        option1,
        option2,
        minBetAmount,
        maxBetAmount,
        _,
        isPrivate,
        category,
    ) =
        get_default_pool_params();

    contract
        .create_pool(
            poolName,
            poolType,
            poolDescription,
            poolImage,
            poolEventSourceUrl,
            poolStartTime,
            poolLockTime,
            poolEndTime,
            option1,
            option2,
            minBetAmount,
            maxBetAmount,
            6,
            isPrivate,
            category,
        );
}

fn get_default_pool_params() -> (
    felt252,
    Pool,
    ByteArray,
    ByteArray,
    ByteArray,
    u64,
    u64,
    u64,
    felt252,
    felt252,
    u256,
    u256,
    u8,
    bool,
    Category,
) {
    let current_time = get_block_timestamp();
    (
        'Default Pool', // poolName
        Pool::WinBet, // poolType
        "Default Description", // poolDescription
        "default_image.jpg", // poolImage
        "https://example.com", // poolEventSourceUrl
        current_time + 86400, // poolStartTime (1 day from now)
        current_time + 172800, // poolLockTime (2 days from now)
        current_time + 259200, // poolEndTime (3 days from now)
        'Option A', // option1
        'Option B', // option2
        1_000_000_000_000_000_000, // minBetAmount (1 STRK)
        10_000_000_000_000_000_000, // maxBetAmount (10 STRK)
        5, // creatorFee (5%)
        false, // isPrivate
        Category::Sports // category
    )
}

#[test]
fn test_vote() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );
    contract.vote(pool_id, 'Team A', 200);

    let pool = contract.get_pool(pool_id);
    assert(pool.totalBetCount == 1, 'Total bet count should be 1');
    assert(pool.totalStakeOption1 == 200, 'Total stake should be 200');
    assert(pool.totalSharesOption1 == 199, 'Total share should be 199');
}

#[test]
fn test_vote_with_user_stake() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );

    let pool = contract.get_pool(pool_id);

    contract.vote(pool_id, 'Team A', 200);

    let user_stake = contract.get_user_stake(pool_id, pool.address);

    assert(user_stake.amount == 200, 'Incorrect amount');
    assert(user_stake.shares == 199, 'Incorrect shares');
    assert(!user_stake.option, 'Incorrect option');
}

#[test]
fn test_successful_get_pool() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool1',
            Pool::WinBet,
            "A simple betting pool1",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );
    let pool = contract.get_pool(pool_id);
    assert(pool.poolName == 'Example Pool1', 'Pool not found');
}

#[test]
#[should_panic(expected: 'Invalid Pool Option')]
fn test_when_invalid_option_is_pass() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );
    contract.vote(pool_id, 'Team C', 200);
}

#[test]
#[should_panic(expected: 'Amount is below minimum')]
fn test_when_min_bet_amount_less_than_required() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );
    contract.vote(pool_id, 'Team A', 10);
}

#[test]
#[should_panic(expected: 'Amount is above maximum')]
fn test_when_max_bet_amount_greater_than_required() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );
    contract.vote(pool_id, 'Team B', 1000000);
}

#[test]
fn test_get_pool_odds() {
    let contract = deploy_predifi();

    // Create a new pool
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );

    contract.vote(pool_id, 'Team A', 100);

    let pool_odds = contract.pool_odds(pool_id);

    assert(pool_odds.option1_odds == 2500, 'Incorrect odds for option 1');
    assert(pool_odds.option2_odds == 7500, 'Incorrect odds for option 2');
}

#[test]
fn test_get_pool_stakes() {
    let contract = deploy_predifi();

    // Create a new pool
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );

    contract.vote(pool_id, 'Team A', 200);

    let pool_stakes = contract.get_pool_stakes(pool_id);

    assert(pool_stakes.amount == 200, 'Incorrect pool stake amount');
    assert(pool_stakes.shares == 199, 'Incorrect pool stake shares');
    assert(!pool_stakes.option, 'Incorrect pool stake option');
}

#[test]
fn test_unique_pool_id() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );
    assert!(pool_id != 0, "not created");
    println!("Pool id: {}", pool_id);
}


#[test]
fn test_unique_pool_id_when_called_twice_in_the_same_execution() {
    let contract = deploy_predifi();
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );
    let pool_id1 = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );

    assert!(pool_id != 0, "not created");
    assert!(pool_id != pool_id1, "they are the same");

    println!("Pool id: {}", pool_id);
    println!("Pool id: {}", pool_id1);
}
#[test]
fn test_get_pool_vote() {
    let contract = deploy_predifi();

    // Create a new pool
    let pool_id = contract
        .create_pool(
            'Example Pool',
            Pool::WinBet,
            "A simple betting pool",
            "image.png",
            "event.com/details",
            1710000000,
            1710003600,
            1710007200,
            'Team A',
            'Team B',
            100,
            10000,
            5,
            false,
            Category::Sports,
        );

    contract.vote(pool_id, 'Team A', 200);

    let pool_vote = contract.get_pool_vote(pool_id);

    assert(!pool_vote, 'Incorrect pool vote');
}

// ERC721 Tests
fn mint_nft(
    contract_address: ContractAddress,
    dispatcher: IERC721MintableDispatcher,
    caller: ContractAddress,
    recipient: ContractAddress,
    token_id: u256,
) {
    start_cheat_caller_address(contract_address, caller);
    dispatcher.mint(recipient, token_id);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_mint_nft() {
    // Accounts
    let alice: ContractAddress = 1.try_into().unwrap();
    let deployer: ContractAddress = get_contract_address();

    // Deploy contract
    let (_, _, nft_contract) = deploy_erc721(deployer);

    // First mint should succeed
    start_cheat_caller_address(nft_contract.contract_address, nft_contract.contract_address);
    nft_contract.mint(alice, 2);
    stop_cheat_caller_address(nft_contract.contract_address);
}

#[test]
fn test_mint_multiple_nfts() {
    let deployer: ContractAddress = get_contract_address();
    let alice: ContractAddress = 1.try_into().unwrap();

    // Deploy contract
    let (_, _, nft_contract) = deploy_erc721(deployer);

    // Mint token id 2 to Alice (since token 1 is minted in constructor)
    start_cheat_caller_address(nft_contract.contract_address, nft_contract.contract_address);
    nft_contract.mint(alice, 2);
    nft_contract.mint(alice, 3);
    nft_contract.mint(alice, 4);
    stop_cheat_caller_address(nft_contract.contract_address);
}

#[test]
#[should_panic(expected: 'Only contract can mint')]
fn test_unauthorized_minting() {
    let deployer: ContractAddress = get_contract_address();
    let (_, _, nft_contract) = deploy_erc721(deployer);
    let recipient: ContractAddress = 1.try_into().unwrap();

    // Try to mint without being the contract - should fail
    nft_contract.mint(recipient, 1_u256);
}
