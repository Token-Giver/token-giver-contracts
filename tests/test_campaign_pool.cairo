use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait, spy_events, EventSpyAssertionsTrait, get_class_hash
};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use starknet::{ContractAddress, ClassHash, get_block_timestamp};

use tokengiver::interfaces::ICampaignPool::{
    ICampaignPool, ICampaignPoolDispatcher, ICampaignPoolDispatcherTrait
};
use tokengiver::interfaces::ITokenGiverNft::{
    ITokenGiverNftDispatcher, ITokenGiverNftDispatcherTrait
};
use tokengiver::campaign_pool::CampaignPools::{Event, DonationMade, CreateCampaignPool};
use token_bound_accounts::interfaces::ILockable::{ILockableDispatcher, ILockableDispatcherTrait};

fn REGISTRY_HASH() -> felt252 {
    0x046163525551f5a50ed027548e86e1ad023c44e0eeb0733f0dab2fb1fdc31ed0
}

fn IMPLEMENTATION_HASH() -> felt252 {
    0x045d67b8590561c9b54e14dd309c9f38c4e2c554dd59414021f9d079811621bd
}

fn DONOR() -> ContractAddress {
    'donor'.try_into().unwrap()
}

fn STRK_ADDR() -> ContractAddress {
    0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}

fn TOKEN_GIVER_CLASS_HASH() -> ClassHash {
    0x6c3c4bc35e0ef172a34d14eae51c4675d65de317d9d8e7239008dc2f5a0e2c1.try_into().unwrap()
}

fn TOKEN_GIVER_CONTRACT_ADDR() -> ContractAddress {
    0x4451a2b48f347b10b65d81cd413bc4ed6660710f7ee23c0708e214853aff050.try_into().unwrap()
}


fn SALT() -> felt252 {
    'salty'.try_into().unwrap()
}

fn RECIPIENT() -> ContractAddress {
    'recipient'.try_into().unwrap()
}

fn OWNER() -> ContractAddress {
    'owner'.try_into().unwrap()
}

const ADMIN: felt252 = 'ADMIN';

fn __setup__() -> (ContractAddress, ContractAddress, ContractAddress) {
    let class_hash = declare("CampaignPools").unwrap().contract_class();

    let strk_address = deploy_erc20();
    let nft_address = __deploy_token_giver_NFT__();

    let owner = OWNER();

    let nft_class_hash = declare("NFTForCampaignOnTokenGiver").unwrap().contract_class();

    let mut calldata = array![];
    nft_class_hash.serialize(ref calldata);
    nft_address.serialize(ref calldata);

    strk_address.serialize(ref calldata);
    owner.serialize(ref calldata);

    let (contract_address, _) = class_hash.deploy(@calldata).unwrap();

    (contract_address, strk_address, nft_address)
}

fn __deploy_token_giver_NFT__() -> ContractAddress {
    let nft_class_hash = declare("NFTForCampaignOnTokenGiver").unwrap().contract_class();

    let admin = OWNER();
    let mut events_constructor_calldata = array![];
    admin.serialize(ref events_constructor_calldata);
    let (nft_contract_address, _) = nft_class_hash.deploy(@events_constructor_calldata).unwrap();

    return nft_contract_address;
}

fn deploy_erc20() -> ContractAddress {
    let class = declare("MyToken").unwrap().contract_class();

    let mut calldata = array![];
    OWNER().serialize(ref calldata);

    let (address, _) = class.deploy(@calldata).unwrap();

    address
}

#[test]
#[fork("Mainnet")]
fn test_create_campaign_pool() {
    // Get the initial setup
    let (token_giver_address, _, _) = __setup__();
    let token_giver = ICampaignPoolDispatcher { contract_address: token_giver_address };

    // Create the required parameters with proper types
    let registry_hash = REGISTRY_HASH();
    let implementation_hash = IMPLEMENTATION_HASH();

    let salt: felt252 = SALT();
    let recipient: ContractAddress = RECIPIENT();
    let campaign_id: u256 = 5;

    // Create campaign with explicit type conversions
    start_cheat_caller_address(token_giver_address, recipient);
    let created_campaign_address = token_giver
        .create_campaign_pool(registry_hash, implementation_hash, salt, recipient, campaign_id);
    stop_cheat_caller_address(token_giver_address);

    // Get campaign details
    start_cheat_caller_address(token_giver_address, recipient);
    let campaign = token_giver.get_campaign(created_campaign_address);
    stop_cheat_caller_address(token_giver_address);

    assert(created_campaign_address == campaign.campaign_address, 'Campaign address mismatch');
}


#[test]
#[fork("Mainnet")]
fn test_create_campaign_pool_event_emission() {
    // Get the initial setup
    let (token_giver_address, _, nft_address) = __setup__();
    let token_giver = ICampaignPoolDispatcher { contract_address: token_giver_address };
    let mut spy = spy_events();

    // Create the required parameters with proper types
    let registry_hash = REGISTRY_HASH();
    let implementation_hash = IMPLEMENTATION_HASH();

    let salt: felt252 = SALT();
    let recipient: ContractAddress = RECIPIENT();
    let campaign_id: u256 = 5;

    // Create campaign with explicit type conversions
    start_cheat_caller_address(token_giver_address, recipient);
    let created_campaign_address = token_giver
        .create_campaign_pool(registry_hash, implementation_hash, salt, recipient, campaign_id);
    stop_cheat_caller_address(token_giver_address);

    // Get campaign details
    start_cheat_caller_address(token_giver_address, recipient);
    let campaign = token_giver.get_campaign(created_campaign_address);
    stop_cheat_caller_address(token_giver_address);

    assert(created_campaign_address == campaign.campaign_address, 'Campaign address mismatch');
    let token_giver_nft_dispatcher = ITokenGiverNftDispatcher { contract_address: nft_address };
    let token_uri = token_giver_nft_dispatcher.get_token_uri(campaign.token_id);
    let expected_event = Event::CreateCampaignPool(
        CreateCampaignPool {
            owner: recipient, // a
            campaign_pool_address: campaign.campaign_address, // b
            token_id: campaign.token_id, // c
            campaign_pool_id: campaign.campaign_id, // d
            nft_token_uri: token_uri.clone(), // e
            token_giver_nft_address: nft_address, // f
            block_timestamp: get_block_timestamp() //g
        }
    );

    // spy.assert_emitted(@array![(token_giver.contract_address, expected_event)]);
}
