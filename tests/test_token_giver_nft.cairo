use core::num::traits::zero::Zero;
use core::starknet::SyscallResultTrait;
use core::traits::{TryInto, Into};
use starknet::{ContractAddress, ClassHash, get_block_timestamp};
use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait, EventSpyAssertionsTrait,
};
use openzeppelin::{token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait}};

use tokengiver::interfaces::ITokenGiverNft::{
    ITokenGiverNftDispatcher, ITokenGiverNftDispatcherTrait
};
use tokengiver::base::errors::Errors::ALREADY_MINTED;
use tokengiver::interfaces::ICampaign::{ICampaignDispatcher, ICampaignDispatcherTrait};

const ADMIN: felt252 = 'ADMIN';
const USER_ONE: felt252 = 'BOB';

fn __setup__() -> ContractAddress {
    // deploy  events
    let nft_class_hash = declare("NFTForCampaignOnTokenGiver").unwrap().contract_class();

    let mut events_constructor_calldata: Array<felt252> = array![ADMIN];
    let (nft_contract_address, _) = nft_class_hash.deploy(@events_constructor_calldata).unwrap();

    return (nft_contract_address);
}

// #[test]
// fn test_metadata() {
//     let nft_contract_address = __setup__();

//     let dispatcher = ERC721ABIDispatcher { contract_address: nft_contract_address };

//     start_prank(CheatTarget::One(nft_contract_address), ADMIN.try_into().unwrap());

//     let nft_name = dispatcher.name();
//     let nft_symbol = dispatcher.symbol();

//     assert(nft_name == "TESTNFT1.0", 'invalid name');
//     assert(nft_symbol == "TNFT1", 'invalid symbol');

//     stop_prank(CheatTarget::One(nft_contract_address));
// }

#[test]
fn test_last_minted_id_on_init_is_zero() {
    let nft_contract_address = __setup__();

    let dispatcher = ITokenGiverNftDispatcher { contract_address: nft_contract_address };

    start_cheat_caller_address(nft_contract_address, ADMIN.try_into().unwrap());
    let last_minted_id = dispatcher.get_last_minted_id();

    assert(last_minted_id.is_zero(), 'last minted id not zero');
    stop_cheat_caller_address(nft_contract_address);
}

#[test]
fn test_get_last_minted_id_after_minting() {
    let nft_contract_address = __setup__();

    let dispatcher = ITokenGiverNftDispatcher { contract_address: nft_contract_address };

    start_cheat_caller_address(nft_contract_address, ADMIN.try_into().unwrap());
    dispatcher.mint_token_giver_nft(USER_ONE.try_into().unwrap());
    let last_minted_id = dispatcher.get_last_minted_id();

    assert(last_minted_id == 1, 'invalid last minted id');

    stop_cheat_caller_address(nft_contract_address);
}

#[test]
fn test_get_user_token_id_after_minting() {
    let nft_contract_address = __setup__();

    let dispatcher = ITokenGiverNftDispatcher { contract_address: nft_contract_address };

    start_cheat_caller_address(nft_contract_address, ADMIN.try_into().unwrap());
    dispatcher.mint_token_giver_nft(USER_ONE.try_into().unwrap());
    let user_token_id = dispatcher.get_user_token_id(USER_ONE.try_into().unwrap());

    assert(user_token_id == 1, 'invalid user token id');
    stop_cheat_caller_address(nft_contract_address);
}
