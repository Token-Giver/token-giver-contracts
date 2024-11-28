use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};
use core::num::traits::zero::Zero;
use core::starknet::SyscallResultTrait;
use core::traits::{TryInto, Into};
use starknet::{ContractAddress};

// Import ERC20 related dispatchers
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use tokengiver::interfaces::ICampaign::{ICampaignDispatcher, ICampaignDispatcherTrait};
use tokengiver::interfaces::ITokenGiverNft::{
    ITokenGiverNftDispatcher, ITokenGiverNftDispatcherTrait
};
use tokengiver::base::errors::Errors::ALREADY_MINTED;

const ADMIN: felt252 = 'ADMIN';
const USER_ONE: felt252 = 'BOB';
const USER_TWO: felt252 = 'JAMES';
const REGISTRY_HASH: felt252 = 0x23a6d289a1e5067d905e195056c322381a78a3bc9ab3b0480f542fad87cc580;
const IMPLEMENTATION_HASH: felt252 =
    0x29d2a1b11dd97289e18042502f11356133a2201dd19e716813fb01fbee9e9a4;

fn deploy_util(contract_name: ByteArray, constructor_calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(contract_name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn __setupNft__() -> ContractAddress {
    let nft_class_hash = declare("TokenGiverNFT").unwrap().contract_class();

    let mut events_constructor_calldata: Array<felt252> = array![ADMIN];
    let (nft_contract_address, _) = nft_class_hash.deploy(@events_constructor_calldata).unwrap();

    return (nft_contract_address);
}

#[test]
fn test_withdrawal_flow() {
    // Explicitly unwrap the DeclareResult
    let erc20_class = declare("erc20").unwrap();

    let contract_class = erc20_class.contract_class();

    // Deploy ERC20 token
    let mut constructor_calldata = array![
        'MyToken', // name
        'MTK', // symbol
        18, // decimals
        1000000, // initial supply
        ADMIN.try_into().unwrap() // initial owner/minter
    ];
    let (token_address, _) = contract_class
        .deploy(@constructor_calldata)
        .expect('Failed to deploy ERC20');

    // Use predefined class hashes for registry and implementation
    let registry_hash: felt252 = 0x23a6d289a1e5067d905e195056c322381a78a3bc9ab3b0480f542fad87cc580;
    let implementation_hash: felt252 =
        0x29d2a1b11dd97289e18042502f11356133a2201dd19e716813fb01fbee9e9a4;

    // Deploy Campaign contract
    let campaign_contract_address = deploy_util("TokengiverCampaign", array![token_address.into()]);

    let nft_contract_address = __setupNft__();

    let CampaignDispatcher = ICampaignDispatcher { contract_address: campaign_contract_address };
    let NftDispatcher = ITokenGiverNftDispatcher { contract_address: nft_contract_address };
    let ERC20Dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Prepare the recipient address
    let recipient = USER_ONE.try_into().unwrap();

    // Mint NFT for recipient
    start_cheat_caller_address(nft_contract_address, ADMIN.try_into().unwrap());
    NftDispatcher.mint_token_giver_nft(recipient);
    stop_cheat_caller_address(nft_contract_address);

    // Create campaign
    start_cheat_caller_address(campaign_contract_address, recipient);
    let created_campaign_address = CampaignDispatcher
        .create_campaign(
            nft_contract_address, registry_hash, implementation_hash, 123, // salt
             recipient
        );
    stop_cheat_caller_address(campaign_contract_address);

    // Pre-fund the campaign directly
    start_cheat_caller_address(token_address, ADMIN.try_into().unwrap());
    ERC20Dispatcher.transfer(created_campaign_address, 100.into());
    stop_cheat_caller_address(token_address);

    // Perform withdrawal as campaign owner
    start_cheat_caller_address(campaign_contract_address, recipient);
    CampaignDispatcher.withdraw(created_campaign_address, 20.into());
    stop_cheat_caller_address(campaign_contract_address);

    // Verify recipient received the tokens
    let recipient_balance = ERC20Dispatcher.balance_of(recipient);
    assert(recipient_balance == 20.into(), 'Incorrect withdrawal amount');
}
