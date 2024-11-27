use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};
use core::num::traits::zero::Zero;
use core::starknet::SyscallResultTrait;
use core::traits::{TryInto, Into};
use starknet::{ContractAddress};
use tokengiver::interfaces::ICampaign::{
    ICampaignDispatcher, ICampaignDispatcherTrait
};
use tokengiver::interfaces::ITokenGiverNft::{
    ITokenGiverNftDispatcher, ITokenGiverNftDispatcherTrait
};
use tokengiver::base::errors::Errors::ALREADY_MINTED;
const ADMIN: felt252 = 'ADMIN';
const USER_ONE: felt252 = 'BOB';
const USER_TWO: felt252 = 'JAMES';

fn deploy_util(contract_name: ByteArray, constructor_calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(contract_name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn __setupNft__() -> ContractAddress {
    // deploy  events
    let nft_class_hash = declare("TokenGiverNFT").unwrap().contract_class();

    let mut events_constructor_calldata: Array<felt252> = array![ADMIN];
    let (nft_contract_address, _) = nft_class_hash.deploy(@events_constructor_calldata).unwrap();

    return (nft_contract_address);
}


#[test]
fn withdraw() {
    let nft_contract_address = __setupNft__();
    let campaign_contract_address = deploy_util("TokengiverCampaign", array![]);
    println!("campaign_contract_address: {:?}", campaign_contract_address);

    let CampaignDispatcher = ICampaignDispatcher { contract_address: campaign_contract_address };
    let NftDispatcher = ITokenGiverNftDispatcher { contract_address: nft_contract_address };

    // admin should mint nft for user 1
    start_cheat_caller_address(nft_contract_address, ADMIN.try_into().unwrap());
    NftDispatcher.mint_token_giver_nft(USER_ONE.try_into().unwrap());
    stop_cheat_caller_address(nft_contract_address);

    // user is creating a campaign
    start_cheat_caller_address(campaign_contract_address, ADMIN.try_into().unwrap());
    CampaignDispatcher.create_campaign(nft_contract_address
        , 20);
    CampaignDispatcher.withdraw(nft_contract_address, 20);
    stop_cheat_caller_address(campaign_contract_address);

}



