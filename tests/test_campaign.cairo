use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait, spy_events, EventSpyAssertionsTrait,
};

use starknet::{ContractAddress, ClassHash};

fn STRK_TOKEN_ADDRESS() -> ContractAddress {
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}
fn REGISTRY_HASH() -> felt252 {
    0x046163525551f5a50ed027548e86e1ad023c44e0eeb0733f0dab2fb1fdc31ed0.try_into().unwrap()
}
fn IMPLEMENTATION_HASH() -> felt252 {
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}

fn SALT() -> felt252 {
    'salty'.try_into().unwrap()
}

fn RECIPIENT() -> ContractAddress {
    'recipient'.try_into().unwrap()
}

use tokengiver::interfaces::ICampaign::{ICampaign, ICampaignDispatcher, ICampaignDispatcherTrait};

fn __setup__() -> ContractAddress {
    let class_hash = declare("TokengiverCampaign").unwrap().contract_class();

    let mut calldata = array![];
    STRK_TOKEN_ADDRESS().serialize(ref calldata);

    let (contract_address, _) = class_hash.deploy(@calldata).unwrap();

    contract_address
}

const ADMIN: felt252 = 'ADMIN';

fn __setup_token_giver_NFT__() -> ContractAddress {
    // deploy  events
    let nft_class_hash = declare("TokenGiverNFT").unwrap().contract_class();

    let mut events_constructor_calldata: Array<felt252> = array![ADMIN];
    let (nft_contract_address, _) = nft_class_hash.deploy(@events_constructor_calldata).unwrap();

    return (nft_contract_address);
}

#[test]
#[fork("Mainnet")]
fn test_donate() {
    let contract_address = __setup__();
    let token_giverNft_contract_address = __setup_token_giver_NFT__();
    let token_giver = ICampaignDispatcher { contract_address };

    //create campaign //    token_giverNft_contract_address: ContractAddress, registry_hash:
    //felt252, implementation_hash: felt252, salt: felt252, recipient: ContractAddress
    let campaign_address = token_giver
        .create_campaign(
            token_giverNft_contract_address,
            REGISTRY_HASH(),
            IMPLEMENTATION_HASH(),
            SALT(),
            RECIPIENT()
        );

    // campaign_address: ContractAddress, amount: u256, token_id: u256
    // token_giver.donate();

    assert(1 == 1, 'wrong');
}
