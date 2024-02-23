module blackjack::single_player_blackjack {
    //dependencies
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self,UID};
    use sui::coin::{Self, Coin};
    use sui::sui::{Self,SUI};
    use sui::balance::{Self, Balance};
    use std::vector;
    use std::hash::sha2_256;

    const ECallerNotHouse: u64 = 4;
    const DEFAULT_MIN_BET: u64 = 1000000000; //1 SUI

    const IN_PROGRESS: u64 = 0;
    const DEALER_WIN: u64 = 1;
    const PLAYER_WIN: u64 = 2;
    const PUSH: u64 = 3;

    struct Game has key, store{
        id: UID,                         // idk about this yet
        owner: address,

        player_cards: vector<u64>,        // cards will be numbered from 1-52
        dealer_cards: vector<u64>,        // same as above

        bet: Balance<SUI>,               // a sui balance
        bet_quantity: u64,
        status: u64,                      // either in progress(0), dealer won(1), player won(2), push(3)
    }


    struct HouseCap has key, store {
        id: UID,
        /// The owner of this AccountCap. Note: this is
        /// derived from an object ID, not a user address
        owner: address,
    }
    struct HouseData has key {
        id: UID,
        balance: Balance<SUI>,
        house: address,
        max_risk_per_game: u64,
    }

     // Constructor, sets the sender as owner / house
    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);
        let owner = tx_context::sender(ctx);
        let house_cap = HouseCap {
            id,
            owner
        };
        transfer::transfer(house_cap, tx_context::sender(ctx))
    }

    public entry fun initialize_house_data(house_cap: &HouseCap, ctx: &mut TxContext) {
        assert!(house_cap.owner == tx_context::sender(ctx), ECallerNotHouse);

        let house_data = HouseData {
            id: object::new(ctx),
            balance: balance::zero(),
            house: tx_context::sender(ctx),
            // initialized 10 10 SUI because I'm broke and its a hackathon lol
            max_risk_per_game: 10 * 1000000000,
        };

        // init function to create the game
        transfer::share_object(house_data);
    }

    /// Create a shared-object BlackJack Game. 
    /// Only a house can create games currently to ensure that we cannot be hacked
    public entry fun create_game(
        house_data: &mut HouseData,
        house_cap: &HouseCap,
        ctx: &mut TxContext
    ) {
        assert!(house_cap.owner == house_data.house, ECallerNotHouse);

        // Initialize the number_risk to be a vector of size 38, starting from 0.
        let game_uid = object::new(ctx);
        let game = Game {
            id: game_uid,
            owner: tx_context::sender(ctx), 
            status: IN_PROGRESS,
            player_cards: vector::empty<u64>(),
            dealer_cards: vector::empty<u64>(),
            bet: balance::zero<SUI>(),
            bet_quantity: 0,
        };
        transfer::share_object(game);
    }
    
    //makes bet the SUI balance of the quantity (quantity is in SUI units, thus why it is multuplied by 1000000000)
    public fun bet(coin: &mut Coin<SUI>, quantity: u64, game: &mut Game, ctx: &mut TxContext) {
        let bet_coin = coin::split(coin, quantity * 1000000000, ctx);
        //need to destroy old coin, smart contracts can't own coins
        let coin_balance = coin::into_balance<SUI>(bet_coin);
        balance::join<SUI>(&mut game.bet, coin_balance);
        game.bet_quantity = quantity * 1000000000;
    }
    public fun deal(game: &mut Game, ctx: &mut TxContext) {
        //first dealt card to player
        vector::push_back<u64>(&mut game.player_cards, generate_random_card(ctx));

        //second dealt card to dealer
        vector::push_back<u64>(&mut game.dealer_cards, generate_random_card(ctx));

        //third dealt card to player
        vector::push_back<u64>(&mut game.player_cards, generate_random_card(ctx));
        //4th card generated at end
    }

    public fun hit(game: &mut Game, ctx: &mut TxContext) {
        //generate another card and add it to the player hand
        vector::push_back<u64>(&mut game.player_cards, generate_random_card(ctx));
    }

    public fun house_win(game: &mut Game, house_data: &mut HouseData, ctx: &mut TxContext) {
        let bet_coin = coin::take(&mut game.bet, game.bet_quantity, ctx);
        coin::put(&mut house_data.balance, bet_coin);
        game.status = DEALER_WIN;
    }

    public fun player_win(game: &mut Game, house_data: &mut HouseData, ctx: &mut TxContext) {
        let player_address = tx_context::sender(ctx);
        let house_payment = coin::take(&mut house_data.balance, balance::value(&game.bet), ctx);
        let bet_coin = coin::take(&mut game.bet, game.bet_quantity, ctx);
        coin::join(&mut bet_coin, house_payment);
        transfer::public_transfer(bet_coin, player_address);
        game.status = DEALER_WIN;
    }

    public fun push(game: &mut Game, ctx: &mut TxContext) {
        let player_address = tx_context::sender(ctx);
        let bet_coin = coin::take(&mut game.bet, game.bet_quantity, ctx);
        transfer::public_transfer(bet_coin, player_address);
        game.status = PUSH;
    }

    public fun get_hand_value(hand: &vector<u64>): u64 {
        let value: u64 = 0;
        //iterate over 
        let numCards = vector::length<u64>(hand);
        let i = 0;
        while(i < numCards) {
            let card = *vector::borrow<u64>(hand, i);
            card = (card % 13) + 1;
            if (card > 10) {
                card = 10;
            };
            value = value + card;
            i = i + 1;
        };
        value
    }

    //if player hand > 21, this should never be called
    public fun stand_and_dealer_turn(game: &mut Game, ctx: &mut TxContext) {
        while(get_hand_value(&game.dealer_cards) < 17) {
            vector::push_back<u64>(&mut game.dealer_cards, generate_random_card(ctx));
            std::debug::print(&game.dealer_cards);
        };
    }
    
    //TODO: figure out how to get rid of the card after it is picked
    public fun generate_random_card(ctx: &mut TxContext): u64 {
        let randomUID = object::new(ctx);
        let id = object::uid_as_inner(&randomUID);
        let bytes = object::id_to_bytes(id);
        object::delete(randomUID);

        let randomVector = sha2_256(bytes);

        let randomCard = safe_selection(52, &randomVector);

        randomCard
    }

    public fun safe_selection(n: u64, rnd: &vector<u8>): u64 {
        let m: u128 = 0;
        let i = 0;
        while (i < 16) {
            m = m << 8;
            let curr_byte = *vector::borrow(rnd, i);
            m = m + (curr_byte as u128);
            i = i + 1;
        };
        let n_128 = (n as u128);
        let module_128  = m % n_128;
        let res = (module_128 as u64);
        res
    }

    /// Function used to top up the house balance. Can be called by anyone.
    /// House can have multiple accounts so giving the treasury balance is not limited.
    /// @param house_data: The HouseData object
    /// @param coin: The coin object that will be used to top up the house balance. The entire coin is consumed
    public entry fun top_up(house_data: &mut HouseData, coin: Coin<SUI>) {        
        let coin_balance = coin::into_balance<SUI>(coin);
        balance::join(&mut house_data.balance, coin_balance);
    }

    /// House can withdraw the entire balance of the house object
    /// @param house_data: The HouseData object
    public entry fun withdraw(house_data: &mut HouseData, quantity: u64, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);
        let coin = coin::take(&mut house_data.balance, quantity, ctx);
        transfer::public_transfer(coin, house_data.house);
    }

    // ----------------------TESTING----------------------------------------------------------------------------------------------
    
    //public fun split(game: &Game) {}, implement this at a later time.
    #[test_only] use sui::coin::mint_for_testing;

    #[test_only] use sui::test_scenario::{Self, Scenario};

    #[test_only]
    public fun mint_account_cap_transfer(
        user: address,
        ctx: &mut TxContext
    ) {
        let house_cap = HouseCap {
            id: object::new(ctx),
            owner: tx_context::sender(ctx)
        };
        transfer::transfer(house_cap, user);
    }

    #[test_only]
    public fun setup_house_for_test (
        scenario: &mut Scenario, house: address
    ) {
        test_scenario::next_tx(scenario, house);
        {
            // Transfer the house cap
            mint_account_cap_transfer(house, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, house);
        {
            let house_cap = test_scenario::take_from_address<HouseCap>(scenario, house);

            // Create the housedata
            initialize_house_data(&house_cap, test_scenario::ctx(scenario));

            test_scenario::return_to_address<HouseCap>(house, house_cap);
        };
        test_scenario::next_tx(scenario, house);
        {
            // Top up the house
            let house_data = test_scenario::take_shared<HouseData>(scenario);
            let house_cap = test_scenario::take_from_address<HouseCap>(scenario, house);
            //give the house 1000 SUI
            top_up(&mut house_data, mint_for_testing<SUI>(1000 * 1000000000, test_scenario::ctx(scenario)));

            // Test create_game
            create_game(&mut house_data, &house_cap, test_scenario::ctx(scenario));
            test_scenario::return_shared(house_data);
            test_scenario::return_to_address<HouseCap>(house, house_cap);
        };

    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // simulation of actual game
    #[test]
    fun play_game() {
        let owner: address = @0xAAAA;
        let player: address = @0xBBBB;
            // begin with house address

        let this_scenario = test_scenario::begin(owner);
        test_scenario::next_tx(&mut this_scenario, owner); 
        {
            setup_house_for_test(&mut this_scenario, owner);

        };
        test_scenario::next_tx(&mut this_scenario,player);
        {
            let test_game = test_scenario::take_shared<Game>(&this_scenario);
            let house_data = test_scenario::take_shared<HouseData>(&this_scenario);

            //for this example, they have 10 SUI
            let player_coin: Coin<SUI> = mint_for_testing<SUI>(10 * 1000000000, test_scenario::ctx(&mut this_scenario));
            
            bet(&mut player_coin, 2, &mut test_game, test_scenario::ctx(&mut this_scenario));
            
            deal(&mut test_game, test_scenario::ctx(&mut this_scenario));
            //    public fun hit(game: &mut Game, ctx: &mut TxContext) {

            hit(&mut test_game, test_scenario::ctx(&mut this_scenario));
            std::debug::print(&test_game.player_cards);
            if(get_hand_value(&test_game.player_cards) > 21) {
                house_win(&mut test_game, &mut house_data, test_scenario::ctx(&mut this_scenario));
                std::debug::print(&test_game.status);
            }
            else {
                stand_and_dealer_turn(&mut test_game, test_scenario::ctx(&mut this_scenario));
                
                let dealer_hand_value = get_hand_value(&test_game.dealer_cards);
                let player_hand_value = get_hand_value(&test_game.player_cards);
                if (player_hand_value > dealer_hand_value || dealer_hand_value > 21) {
                    player_win(&mut test_game, &mut house_data, test_scenario::ctx(&mut this_scenario));
                    std::debug::print(&test_game.status);
                }
                else if (dealer_hand_value > player_hand_value) {
                    house_win(&mut test_game, &mut house_data, test_scenario::ctx(&mut this_scenario));
                    std::debug::print(&test_game.status);


                }
                else {
                    push(&mut test_game, test_scenario::ctx(&mut this_scenario)); //implicitly, this should mean that the two values are equal to each other
                    std::debug::print(&test_game.status);
                };
            };
            coin::burn_for_testing(player_coin);
            test_scenario::return_shared(test_game);
            test_scenario::return_shared(house_data);
        };
        test_scenario::end(this_scenario);
    }
    

}