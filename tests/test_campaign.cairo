use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait, spy_events, EventSpyAssertionsTrait,
};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use starknet::{ContractAddress, ClassHash};

use tokengiver::interfaces::ICampaign::{ICampaign, ICampaignDispatcher, ICampaignDispatcherTrait};

// fn STRK_TOKEN_ADDRESS() -> ContractAddress {
//     0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
// }
fn REGISTRY_HASH() -> felt252 {
    0x046163525551f5a50ed027548e86e1ad023c44e0eeb0733f0dab2fb1fdc31ed0.try_into().unwrap()
}
fn IMPLEMENTATION_HASH() -> felt252 {
    0x45d67b8590561c9b54e14dd309c9f38c4e2c554dd59414021f9d079811621bd.try_into().unwrap()
}

fn DONOR() -> ContractAddress {
    'donor'.try_into().unwrap()
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


fn __setup__() -> (ContractAddress, ContractAddress) {
    let class_hash = declare("TokengiverCampaign").unwrap().contract_class();
    let strk_address = deploy_erc20();

    let mut calldata = array![];
    strk_address.serialize(ref calldata);

    let (contract_address, _) = class_hash.deploy(@calldata).unwrap();

    (contract_address, strk_address)
}


fn __setup_token_giver_NFT__() -> ContractAddress {
    // deploy  events
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
    let (token_giver_address, strk_address) = __setup__();
    let token_giverNft_contract_address = __setup_token_giver_NFT__();
    let token_giver = ICampaignDispatcher { contract_address: token_giver_address };
    let strk_dispatcher = IERC20Dispatcher { contract_address: strk_address };
    let random_id = 1;

    start_cheat_caller_address(token_giver_address, RECIPIENT());
    let campaign_address = token_giver
    .create_campaign(
        token_giverNft_contract_address,
        REGISTRY_HASH(),
        IMPLEMENTATION_HASH(),
        SALT(),
        RECIPIENT()
    );
    stop_cheat_caller_address(token_giver_address);
    
    /// Transfer STRK to Donor
    start_cheat_caller_address(strk_address, OWNER());
    let amount = 2000000; // 
    strk_dispatcher.transfer(DONOR(), amount);
    assert(strk_dispatcher.balance_of(DONOR()) >= amount, 'strk bal too low');
    stop_cheat_caller_address(strk_address);
    
    start_cheat_caller_address(strk_address, DONOR());
    strk_dispatcher.approve(token_giver_address, amount);
    stop_cheat_caller_address(strk_address);

    start_cheat_caller_address(token_giver_address, DONOR());
    token_giver.donate(campaign_address, amount, random_id);
    stop_cheat_caller_address(token_giver_address);

    assert(strk_dispatcher.balance_of(DONOR()) == 0, 'wrong balance');
}
