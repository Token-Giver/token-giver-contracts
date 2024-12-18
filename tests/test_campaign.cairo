use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait, spy_events, EventSpyAssertionsTrait, get_class_hash
};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use starknet::{ContractAddress, ClassHash, get_block_timestamp};

use tokengiver::interfaces::ICampaign::{ICampaign, ICampaignDispatcher, ICampaignDispatcherTrait};
use tokengiver::campaign::TokengiverCampaign::{Event, DonationMade, WithdrawalMade, CreateCampaign};
use token_bound_accounts::interfaces::ILockable::{ILockableDispatcher, ILockableDispatcherTrait};

fn REGISTRY_HASH() -> felt252 {
    0x046163525551f5a50ed027548e86e1ad023c44e0eeb0733f0dab2fb1fdc31ed0.try_into().unwrap()
}
fn IMPLEMENTATION_HASH() -> felt252 {
    0x45d67b8590561c9b54e14dd309c9f38c4e2c554dd59414021f9d079811621bd.try_into().unwrap()
}

fn DONOR() -> ContractAddress {
    'donor'.try_into().unwrap()
}

fn STRK_ADDR() -> ContractAddress {
    0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
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
    let class_hash = declare("TokengiverCampaign").unwrap().contract_class();
    let strk_address = deploy_erc20();
    let nft_address = __deploy_token_giver_NFT__();

    let mut calldata = array![];
    nft_address.serialize(ref calldata);
    strk_address.serialize(ref calldata);

    let (contract_address, _) = class_hash.deploy(@calldata).unwrap();

    (contract_address, strk_address, nft_address)
}

fn __deploy_token_giver_NFT__() -> ContractAddress {
    let nft_class_hash = declare("TokenGiverNFT").unwrap().contract_class();

    let mut events_constructor_calldata: Array<felt252> = array![ADMIN];
    let (nft_contract_address, _) = nft_class_hash.deploy(@events_constructor_calldata).unwrap();

    return (nft_contract_address);
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
fn test_donate() {
    let (token_giver_address, strk_address, _) = __setup__();
    let token_giver = ICampaignDispatcher { contract_address: token_giver_address };
    let strk_dispatcher = IERC20Dispatcher { contract_address: strk_address };
    let random_id = 1;

    //create campaign
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let campaign_address = token_giver
        .create_campaign(REGISTRY_HASH(), IMPLEMENTATION_HASH(), SALT());

    stop_cheat_caller_address(token_giver_address);

    /// Transfer STRK to Donor
    start_cheat_caller_address(strk_address, OWNER());
    let amount = 35; // 
    strk_dispatcher.transfer(DONOR(), amount);
    assert(strk_dispatcher.balance_of(DONOR()) >= amount, 'strk bal too low');
    stop_cheat_caller_address(strk_address);

    // approve allowance
    start_cheat_caller_address(strk_address, DONOR());
    strk_dispatcher.approve(token_giver_address, amount);
    stop_cheat_caller_address(strk_address);

    // donate
    start_cheat_caller_address(token_giver_address, DONOR());
    token_giver.donate(campaign_address, amount, random_id);
    stop_cheat_caller_address(token_giver_address);
    assert(strk_dispatcher.balance_of(DONOR()) == 0, 'wrong balance');
    assert(token_giver.get_donations(campaign_address) == amount, 'wrong donation amount');
    assert(token_giver.get_donation_count(campaign_address) == 1, 'wrong donation amount');
}


#[test]
#[fork("Mainnet")]
fn test_donate_event_emission() {
    let (token_giver_address, strk_address, _) = __setup__();
    let token_giver = ICampaignDispatcher { contract_address: token_giver_address };
    let strk_dispatcher = IERC20Dispatcher { contract_address: strk_address };
    let random_id = 1;
    let mut spy = spy_events();

    //create campaign
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let campaign_address = token_giver
        .create_campaign(REGISTRY_HASH(), IMPLEMENTATION_HASH(), SALT());

    stop_cheat_caller_address(token_giver_address);

    /// Transfer STRK to Donor
    start_cheat_caller_address(strk_address, OWNER());
    let amount = 2000000; // 
    strk_dispatcher.transfer(DONOR(), amount);
    assert(strk_dispatcher.balance_of(DONOR()) >= amount, 'strk bal too low');
    stop_cheat_caller_address(strk_address);

    // approve allowance
    start_cheat_caller_address(strk_address, DONOR());
    strk_dispatcher.approve(token_giver_address, amount);
    stop_cheat_caller_address(strk_address);

    // donate
    start_cheat_caller_address(token_giver_address, DONOR());
    token_giver.donate(campaign_address, amount, random_id);
    stop_cheat_caller_address(token_giver_address);

    // test DonationMade event emission
    let expected_event = Event::DonationMade(
        DonationMade {
            campaign_id: random_id,
            donor_address: DONOR(),
            amount: amount,
            token_id: random_id,
            block_timestamp: get_block_timestamp(),
        }
    );

    spy.assert_emitted(@array![(token_giver.contract_address, expected_event)]);
}

#[test]
#[fork("Mainnet")]
fn test_withdraw() {
    let (token_giver_address, strk_address, _) = __setup__();
    let token_giver = ICampaignDispatcher { contract_address: token_giver_address };
    let strk_dispatcher = IERC20Dispatcher { contract_address: strk_address };
    let random_id = 1;

    //create campaign
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let campaign_address = token_giver
        .create_campaign(REGISTRY_HASH(), IMPLEMENTATION_HASH(), SALT());
    stop_cheat_caller_address(token_giver_address);

    /// Transfer STRK to Donor
    start_cheat_caller_address(strk_address, OWNER());
    let amount = 2000000; // 
    strk_dispatcher.transfer(DONOR(), amount);
    assert(strk_dispatcher.balance_of(DONOR()) == amount, 'transfer failed');
    stop_cheat_caller_address(strk_address);

    // approve allowance
    start_cheat_caller_address(strk_address, DONOR());
    strk_dispatcher.approve(token_giver_address, amount);
    stop_cheat_caller_address(strk_address);

    // donate
    start_cheat_caller_address(token_giver_address, DONOR());
    token_giver.donate(campaign_address, amount, random_id);
    stop_cheat_caller_address(token_giver_address);
    assert(strk_dispatcher.balance_of(campaign_address) == amount, 'donation failed');

    // Campaign address (TBA) -> approves token giver contract
    start_cheat_caller_address(strk_address, campaign_address);
    strk_dispatcher.approve(token_giver_address, amount);
    stop_cheat_caller_address(strk_address);

    // Campaign creator (RECIPIENT()) -> withdraws donations
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    token_giver.withdraw(campaign_address, amount);
    stop_cheat_caller_address(token_giver_address);

    assert(strk_dispatcher.balance_of(RECIPIENT()) == amount, 'withdrawal failed');
    assert(token_giver.get_available_withdrawal(campaign_address) == 0, 'withdrawal failed');
}


#[test]
#[fork("Mainnet")]
fn test_create_campaign() {
    let (token_giver_address, _, _) = __setup__();
    let token_giver = ICampaignDispatcher { contract_address: token_giver_address };

    // create campaign
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let created_campaign_address = token_giver
        .create_campaign(REGISTRY_HASH(), IMPLEMENTATION_HASH(), SALT());
    stop_cheat_caller_address(token_giver_address);

    // // get campagin
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let campaign = token_giver.get_campaign(created_campaign_address);
    stop_cheat_caller_address(token_giver_address);

    assert(created_campaign_address == campaign.campaign_address, 'create campaign failed');
}


#[test]
#[fork("Mainnet")]
fn test_create_campaign_event_emission() {
    let (token_giver_address, _, nft_address) = __setup__();
    let token_giver = ICampaignDispatcher { contract_address: token_giver_address };
    let mut spy = spy_events();

    // create campaign
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let created_campaign_address = token_giver
        .create_campaign(REGISTRY_HASH(), IMPLEMENTATION_HASH(), SALT());
    stop_cheat_caller_address(token_giver_address);

    // get campagin
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let campaign = token_giver.get_campaign(created_campaign_address);

    stop_cheat_caller_address(token_giver_address);
    assert(created_campaign_address == campaign.campaign_address, 'create campaign failed');

    let expected_event = Event::CreateCampaign(
        CreateCampaign {
            owner: campaign.campaign_owner,
            campaign_address: campaign.campaign_address,
            token_id: campaign.token_id,
            token_giver_nft_address: nft_address
        }
    );

    spy.assert_emitted(@array![(token_giver.contract_address, expected_event)]);
}


#[test]
#[fork("Mainnet")]
fn test_withdraw_event_emission() {
    let (token_giver_address, strk_address, _) = __setup__();
    let token_giver = ICampaignDispatcher { contract_address: token_giver_address };
    let strk_dispatcher = IERC20Dispatcher { contract_address: strk_address };
    let random_id = 1;
    let mut spy = spy_events();

    //create campaign
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let campaign_address = token_giver
        .create_campaign(REGISTRY_HASH(), IMPLEMENTATION_HASH(), SALT());
    stop_cheat_caller_address(token_giver_address);

    /// Transfer STRK to Donor
    start_cheat_caller_address(strk_address, OWNER());
    let amount = 2000000; // 
    strk_dispatcher.transfer(DONOR(), amount);
    assert(strk_dispatcher.balance_of(DONOR()) == amount, 'transfer failed');
    stop_cheat_caller_address(strk_address);

    // approve allowance
    start_cheat_caller_address(strk_address, DONOR());
    strk_dispatcher.approve(token_giver_address, amount);
    stop_cheat_caller_address(strk_address);

    // donate
    start_cheat_caller_address(token_giver_address, DONOR());
    token_giver.donate(campaign_address, amount, random_id);
    stop_cheat_caller_address(token_giver_address);
    assert(strk_dispatcher.balance_of(campaign_address) == amount, 'donation failed');

    // Campaign address (TBA) -> approves token giver contract
    start_cheat_caller_address(strk_address, campaign_address);
    strk_dispatcher.approve(token_giver_address, amount);
    stop_cheat_caller_address(strk_address);

    // Campaign creator (RECIPIENT()) -> withdraws donations
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    token_giver.withdraw(campaign_address, amount);
    stop_cheat_caller_address(token_giver_address);

    assert(strk_dispatcher.balance_of(RECIPIENT()) == amount, 'withdrawal failed');
    assert(token_giver.get_available_withdrawal(campaign_address) == 0, 'withdrawal failed');

    let expected_event = Event::WithdrawalMade(
        WithdrawalMade {
            campaign_address: campaign_address,
            recipient: RECIPIENT(),
            amount: amount,
            block_timestamp: get_block_timestamp(),
        }
    );

    spy.assert_emitted(@array![(token_giver.contract_address, expected_event)]);
}

#[test]
fn test_upgradability() {
    let class_hash = declare("TokengiverCampaign").unwrap().contract_class();
    let strk_address = deploy_erc20();
    let nft_address = __deploy_token_giver_NFT__();

    let mut calldata = array![];
    nft_address.serialize(ref calldata);
    strk_address.serialize(ref calldata);

    let (contract_address, _) = class_hash.deploy(@calldata).unwrap();

    let campaign_dispatcher = ICampaignDispatcher { contract_address };
    let new_class_hash = declare("TokengiverCampaign").unwrap().contract_class().class_hash;
    campaign_dispatcher.upgrade(*new_class_hash);
}


#[test]
#[should_panic]
fn test_upgradability_should_fail_if_not_owner_tries_to_update() {
    let class_hash = declare("TokengiverCampaign").unwrap().contract_class();
    let strk_address = deploy_erc20();
    let nft_address = __deploy_token_giver_NFT__();

    let mut calldata = array![];
    nft_address.serialize(ref calldata);
    strk_address.serialize(ref calldata);

    let (contract_address, _) = class_hash.deploy(@calldata).unwrap();

    let campaign_dispatcher = ICampaignDispatcher { contract_address };
    let new_class_hash = declare("TokengiverCampaign").unwrap().contract_class().class_hash;
    start_cheat_caller_address(contract_address, starknet::contract_address_const::<0x123>());
    campaign_dispatcher.upgrade(*new_class_hash);
}

#[test]
#[fork("Mainnet")]
fn test_is_locked() {
    let (token_giver_address, _, _) = __setup__();
    let token_giver = ICampaignDispatcher { contract_address: token_giver_address };

    //create campaign
    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let campaign_address = token_giver
        .create_campaign(REGISTRY_HASH(), IMPLEMENTATION_HASH(), SALT());
    stop_cheat_caller_address(token_giver_address);

    let campaign_contract = ILockableDispatcher { contract_address: campaign_address };
    let (is_locked, _) = campaign_contract.is_locked();
    assert(is_locked == false, 'wrong lock value');
}
