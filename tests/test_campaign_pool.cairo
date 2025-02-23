use core::num::traits::zero::Zero;
use core::starknet::SyscallResultTrait;
use core::traits::{TryInto, Into};
use starknet::{ContractAddress, ClassHash, get_block_timestamp};
use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait, spy_events, EventSpyAssertionsTrait,
};

use tokengiver::interfaces::ICampaignPool::{
    ICampaignPoolDispatcher, 
    ICampaignPoolDispatcherTrait
};
use tokengiver::campaign_pool::CampaignPools::{
    Event, 
    ApplicationMade
};
use tokengiver::base::errors::Errors::{
    INVALID_CAMPAIGN_ADDRESS, 
    INVALID_POOL_ADDRESS, 
    INVALID_AMOUNT
};

fn setup_campaign_pool() -> (ContractAddress, ContractAddress, ContractAddress) {
    // Deploy contract instances needed for testing
    let class_hash = declare("CampaignPools").unwrap().contract_class();
    
    // Deploy token giver NFT contract
    let nft_class_hash = declare("NFTForCampaignOnTokenGiver").unwrap().contract_class();
    let admin = starknet::contract_address_const::<'ADMIN'>();
    let mut events_constructor_calldata = array![];
    admin.serialize(ref events_constructor_calldata);
    let (nft_contract_address, _) = nft_class_hash.deploy(@events_constructor_calldata).unwrap();
    
    // Deploy ERC20 token contract for STRK
    let erc20_class_hash = declare("MyToken").unwrap().contract_class();
    let mut token_calldata = array![];
    admin.serialize(ref token_calldata);
    let (strk_address, _) = erc20_class_hash.deploy(@token_calldata).unwrap();
    
    // Deploy campaign pool contract
    let mut calldata = array![];
    nft_class_hash.class_hash.serialize(ref calldata);
    nft_contract_address.serialize(ref calldata);
    strk_address.serialize(ref calldata);
    admin.serialize(ref calldata);
    let (pool_contract_address, _) = class_hash.deploy(@calldata).unwrap();
    
    (pool_contract_address, strk_address, nft_contract_address)
}

fn create_test_campaign_pool(pool_contract_address: ContractAddress) -> ContractAddress {
    // Implementation depends on how campaign pools are created
    // This is a placeholder
    let campaign_pool_dispatcher = ICampaignPoolDispatcher { contract_address: pool_contract_address };
    
    start_cheat_caller_address(pool_contract_address, starknet::contract_address_const::<'ADMIN'>());
    let registry_hash: felt252 = 'registry_hash';
    let implementation_hash: felt252 = 'implementation_hash';
    let salt: felt252 = 'salt';
    let recipient = starknet::contract_address_const::<'USER'>();
    let campaign_pool_id: u256 = 1;
    
    let campaign_pool_address = campaign_pool_dispatcher.create_campaign_pool(
        registry_hash, implementation_hash, salt, recipient, campaign_pool_id
    );
    stop_cheat_caller_address(pool_contract_address);
    
    campaign_pool_address
}

#[test]
fn test_apply_to_campaign_pool_success() {
    // Setup campaign pool contracts
    let (pool_contract_address, _, _) = setup_campaign_pool();
    let pool_dispatcher = ICampaignPoolDispatcher { contract_address: pool_contract_address };
    
    // Create a campaign pool
    let campaign_pool_address = create_test_campaign_pool(pool_contract_address);
    
    // Create a mock campaign address
    let campaign_address = starknet::contract_address_const::<'CAMPAIGN'>();
    
    // Apply to the campaign pool
    let amount: u256 = 1000;
    let user = starknet::contract_address_const::<'USER'>();
    
    start_cheat_caller_address(pool_contract_address, user);
    
    // Set up spy for events
    let mut spy = spy_events();
    
    pool_dispatcher.apply_to_campaign_pool(campaign_address, campaign_pool_address, amount);
    
    // Verify that the correct event was emitted
    let expected_event = Event::ApplicationMade(
        ApplicationMade {
            campaign_pool_address,
            campaign_address,
            recipient: user,
            amount,
            block_timestamp: get_block_timestamp(),
        }
    );
    
    spy.assert_emitted(@array![(pool_dispatcher.contract_address, expected_event)]);
    
    stop_cheat_caller_address(pool_contract_address);
}

#[test]
#[should_panic(expected: ('TGN: invalid campaign address!',))]
fn test_apply_to_campaign_pool_invalid_campaign() {
    // Setup campaign pool contracts
    let (pool_contract_address, _, _) = setup_campaign_pool();
    let pool_dispatcher = ICampaignPoolDispatcher { contract_address: pool_contract_address };
    
    // Create a campaign pool
    let campaign_pool_address = create_test_campaign_pool(pool_contract_address);
    
    // Use a zero address as invalid campaign address
    let invalid_campaign_address = starknet::contract_address_const::<0>();
    
    // Apply to the campaign pool with invalid campaign address
    let amount: u256 = 1000;
    let user = starknet::contract_address_const::<'USER'>();
    
    start_cheat_caller_address(pool_contract_address, user);
    pool_dispatcher.apply_to_campaign_pool(invalid_campaign_address, campaign_pool_address, amount);
    stop_cheat_caller_address(pool_contract_address);
}

#[test]
#[should_panic(expected: ('TGN: invalid pool address!',))]
fn test_apply_to_campaign_pool_invalid_pool() {
    // Setup campaign pool contracts
    let (pool_contract_address, _, _) = setup_campaign_pool();
    let pool_dispatcher = ICampaignPoolDispatcher { contract_address: pool_contract_address };
    
    // Use a valid campaign address
    let campaign_address = starknet::contract_address_const::<'CAMPAIGN'>();
    
    // Use an invalid pool address
    let invalid_pool_address = starknet::contract_address_const::<0>();
    
    // Apply to the campaign pool with invalid pool address
    let amount: u256 = 1000;
    let user = starknet::contract_address_const::<'USER'>();
    
    start_cheat_caller_address(pool_contract_address, user);
    pool_dispatcher.apply_to_campaign_pool(campaign_address, invalid_pool_address, amount);
    stop_cheat_caller_address(pool_contract_address);
}

#[test]
#[should_panic(expected: ('TGN: invalid amount!',))]
fn test_apply_to_campaign_pool_zero_amount() {
    // Setup campaign pool contracts
    let (pool_contract_address, _, _) = setup_campaign_pool();
    let pool_dispatcher = ICampaignPoolDispatcher { contract_address: pool_contract_address };
    
    // Create a campaign pool
    let campaign_pool_address = create_test_campaign_pool(pool_contract_address);
    
    // Use a valid campaign address
    let campaign_address = starknet::contract_address_const::<'CAMPAIGN'>();
    
    // Apply to the campaign pool with zero amount
    let zero_amount: u256 = 0;
    let user = starknet::contract_address_const::<'USER'>();
    
    start_cheat_caller_address(pool_contract_address, user);
    pool_dispatcher.apply_to_campaign_pool(campaign_address, campaign_pool_address, zero_amount);
    stop_cheat_caller_address(pool_contract_address);
}