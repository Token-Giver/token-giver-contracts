use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait, spy_events, EventSpyAssertionsTrait,
};

use tokengiver::interfaces::ICampaign::ICampaign;

fn __setup__() -> ContractAddress {
    let class_hash = declare("TokengiverCampaign").unwrap().contract_class();

    let mut call_data: Array<felt252> = array![];
    let (contract_address, _) = class_hash.deploy(@call_data).unwrap();

    return (contract_address);
}

#[test]
fn test_donate() {

}