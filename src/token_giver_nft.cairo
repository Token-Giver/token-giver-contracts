#[starknet::contract]
pub mod TokenGiversNFT {
    // *************************************************************************
    //                             IMPORTS
    // *************************************************************************
    use starknet::{ContractAddress, get_block_timestamp, ClassHash, class_hash::class_hash_const};
    use core::num::traits::zero::Zero;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use openzeppelin::{account, access::ownable::OwnableComponent};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, StoragePointerWriteAccess, StoragePointerReadAccess, StorageMapReadAccess,
        StorageMapWriteAccess
    };
    use tokengiver::interfaces::ITokenGiverNft;

    // *************************************************************************
    //                             COMPONENTS
    // *************************************************************************
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // ERC721 Mixin
    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    /// Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // *************************************************************************
    //                             STORAGE
    // *************************************************************************
    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        admin: ContractAddress,
        last_minted_id: u256,
        mint_timestamp: Map<u256, u64>,
        user_token_id: Map<ContractAddress, u256>,
    }

    // *************************************************************************
    //                             EVENTS
    // *************************************************************************
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    // *************************************************************************
    //                              CONSTRUCTOR
    // *************************************************************************
    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.ownable.initializer(admin);
        self
            .erc721
            .initializer(
                "TokenGiverNFT",
                "TGNFT",
                "ipfs://bafkreictgoc5ty6lgnnzexlmyiv56tmxtuflivgke7kuf7saffws7iij3i/"
            );
    }


    #[abi(embed_v0)]
    impl TokenGiverImpl of ITokenGiverNft::ITokenGiverNft<ContractState> {
        // *************************************************************************
        //                            EXTERNAL
        // *************************************************************************

        fn mint_token_giver_nft(ref self: ContractState, address: ContractAddress) -> u256 {
            let mut token_id = self.last_minted_id.read() + 1;
            self.erc721.mint(address, token_id);
            let timestamp: u64 = get_block_timestamp();

            self.user_token_id.write(address, token_id);
            self.last_minted_id.write(token_id);
            self.mint_timestamp.write(token_id, timestamp);
            token_id
        }


        fn get_user_token_id(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_token_id.read(user)
        }


        fn get_last_minted_id(self: @ContractState) -> u256 {
            self.last_minted_id.read()
        }


        fn get_token_mint_timestamp(self: @ContractState, token_id: u256) -> u64 {
            self.mint_timestamp.read(token_id)
        }

        fn get_token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721.token_uri(token_id)
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // This function can only be called by the owner
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
