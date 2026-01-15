// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";

import "./OrderBookPodStorage.sol";
import "../../interfaces/event/IOrderBookPod.sol";

contract OrderBookPod is Initializable, OwnableUpgradeable, PausableUpgradeable, OrderBookPodStorage {
    modifier onlyOrderBookManager() {
        require(msg.sender == orderBookManager, "OrderBookPod: only orderBookManager");
        _;
    }

    modifier onlyEventPod() {
        require(msg.sender == eventPod, "OrderBookPod: only eventPod");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address _eventPod,
        address _fundingPod,
        address _feeVaultPod,
        address _orderBookManager
    ) public initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();

        eventPod = _eventPod;
        fundingPod = _fundingPod;
        feeVaultPod = _feeVaultPod;
        orderBookManager = _orderBookManager;
    }

    // ------------------------------------------------------------
    // External
    // ------------------------------------------------------------
    function placeOrder(
        uint256 eventId,
        uint256 outcomeId,
        OrderSide side,
        uint256 price,
        uint256 amount,
        address tokenAddress
    ) external whenNotPaused onlyOrderBookManager returns (uint256 orderId) {
        if (!supportedEvents[eventId]) revert EventNotSupported(eventId);
        if (!supportedOutcomes[eventId][outcomeId]) {
            revert OutcomeNotSupported(eventId, outcomeId);
        }
        if (eventSettled[eventId]) revert EventAlreadySettled(eventId);
        if (price == 0 || price > MAX_PRICE) revert InvalidPrice(price);
        if (price % TICK_SIZE != 0) revert PriceNotAlignedWithTickSize(price);
        if (amount == 0) revert InvalidAmount(amount);

        // Funding module: Lock funds required for order (implemented by funding module)
        // IFundingPod(fundingPod).lockOnOrderPlaced(msg.sender, tokenAddress, amount, eventId, outcomeId);

        orderId = nextOrderId++;
        orders[orderId] = Order({
            orderId: orderId,
            user: msg.sender,
            eventId: eventId,
            outcomeId: outcomeId,
            side: side,
            price: price,
            amount: amount,
            filledAmount: 0,
            remainingAmount: amount,
            status: OrderStatus.Pending,
            timestamp: block.timestamp,
            tokenAddress: tokenAddress
        });
        userOrders[msg.sender].push(orderId);

        _matchOrder(orderId);

        if (orders[orderId].status == OrderStatus.Pending || orders[orderId].status == OrderStatus.Partial) {
            _addToOrderBook(orderId);
        }

        emit OrderPlaced(orderId, msg.sender, eventId, outcomeId, side, price, amount);
    }

    function cancelOrder(uint256 orderId) external onlyOrderBookManager {
        Order storage order = orders[orderId];

        if (order.status != OrderStatus.Pending && order.status != OrderStatus.Partial) {
            revert CannotCancelOrder(orderId);
        }
        if (eventSettled[order.eventId]) {
            revert EventAlreadySettled(order.eventId);
        }

        _removeFromOrderBook(orderId);

        order.status = OrderStatus.Cancelled;

        if (order.remainingAmount > 0) {
            // Funding module: Unlock remaining unfilled funds (implemented by funding module)
            // IFundingPod(fundingPod).unlockOnOrderCancelled(order.user, order.tokenAddress, order.remainingAmount, order.eventId, order.outcomeId);
        }

        emit OrderCancelled(orderId, order.user, order.remainingAmount);
    }

    function settleEvent(uint256 eventId, uint256 winningOutcomeId) external onlyEventPod {
        if (!supportedEvents[eventId]) revert EventNotSupported(eventId);
        if (eventSettled[eventId]) revert EventAlreadySettled(eventId);
        if (!supportedOutcomes[eventId][winningOutcomeId]) {
            revert OutcomeNotSupported(eventId, winningOutcomeId);
        }

        eventSettled[eventId] = true;
        eventResults[eventId] = winningOutcomeId;

        _cancelAllPendingOrders(eventId);
        _settlePositions(eventId, winningOutcomeId);

        emit EventSettled(eventId, winningOutcomeId);
    }

    function addEvent(uint256 eventId, uint256[] calldata outcomeIds) external onlyOrderBookManager {
        require(!supportedEvents[eventId], "OrderBookPod: event exists");
        supportedEvents[eventId] = true;

        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint256 outcomeId = outcomeIds[i];
            require(outcomeId > 0, "OrderBookPod: invalid outcome");
            supportedOutcomes[eventId][outcomeId] = true;
            eventOrderBook.supportedOutcomes.push(outcomeId);
        }

        emit EventAdded(eventId, outcomeIds);
    }

    function getBestBid(uint256 eventId, uint256 outcomeId) external view returns (uint256 price, uint256 amount) {
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[outcomeId];

        if (outcomeOrderBook.buyPriceLevels.length > 0) {
            price = outcomeOrderBook.buyPriceLevels[0];
            amount = _totalAtPrice(outcomeOrderBook.buyOrdersByPrice[price]);
        }
    }

    function getBestAsk(uint256 eventId, uint256 outcomeId) external view returns (uint256 price, uint256 amount) {
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[outcomeId];

        if (outcomeOrderBook.sellPriceLevels.length > 0) {
            price = outcomeOrderBook.sellPriceLevels[0];
            amount = _totalAtPrice(outcomeOrderBook.sellOrdersByPrice[price]);
        }
    }

    // ------------------------------------------------------------
    // Internal: matching order execution
    // ------------------------------------------------------------
    function _matchOrder(uint256 orderId) internal {
        Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[order.outcomeId];

        if (order.side == OrderSide.Buy) {
            _matchBuy(orderId, outcomeOrderBook);
        } else {
            _matchSell(orderId, outcomeOrderBook);
        }
    }

    function _matchBuy(uint256 buyOrderId, OutcomeOrderBook storage book) internal {
        Order storage buyOrder = orders[buyOrderId];

        for (uint256 i = 0; i < book.sellPriceLevels.length && buyOrder.remainingAmount > 0; i++) {
            uint256 sellPrice = book.sellPriceLevels[i];
            if (sellPrice > buyOrder.price) break;

            uint256[] storage sellOrders = book.sellOrdersByPrice[sellPrice];
            for (uint256 j = 0; j < sellOrders.length && buyOrder.remainingAmount > 0; j++) {
                uint256 sellOrderId = sellOrders[j];
                Order storage sellOrder = orders[sellOrderId];
                if (sellOrder.status == OrderStatus.Cancelled || sellOrder.remainingAmount == 0) continue;
                if (buyOrder.eventId != sellOrder.eventId) {
                    revert EventMismatch(buyOrder.eventId, sellOrder.eventId);
                }
                if (buyOrder.outcomeId != sellOrder.outcomeId) {
                    revert OutcomeMismatch(buyOrder.outcomeId, sellOrder.outcomeId);
                }
                _executeMatch(buyOrderId, sellOrderId);
            }
        }
    }

    function _matchSell(uint256 sellOrderId, OutcomeOrderBook storage book) internal {
        Order storage sellOrder = orders[sellOrderId];

        for (uint256 i = 0; i < book.buyPriceLevels.length && sellOrder.remainingAmount > 0; i++) {
            uint256 buyPrice = book.buyPriceLevels[i];
            if (buyPrice < sellOrder.price) break;

            uint256[] storage buyOrders = book.buyOrdersByPrice[buyPrice];
            for (uint256 j = 0; j < buyOrders.length && sellOrder.remainingAmount > 0; j++) {
                uint256 buyOrderId = buyOrders[j];
                Order storage buyOrder = orders[buyOrderId];
                if (buyOrder.status == OrderStatus.Cancelled || buyOrder.remainingAmount == 0) continue;
                if (buyOrder.eventId != sellOrder.eventId) {
                    revert EventMismatch(buyOrder.eventId, sellOrder.eventId);
                }
                if (buyOrder.outcomeId != sellOrder.outcomeId) {
                    revert OutcomeMismatch(buyOrder.outcomeId, sellOrder.outcomeId);
                }
                _executeMatch(buyOrderId, sellOrderId);
            }
        }
    }

    function _executeMatch(uint256 buyOrderId, uint256 sellOrderId) internal {
        Order storage buyOrder = orders[buyOrderId];
        Order storage sellOrder = orders[sellOrderId];

        uint256 matchAmount =
            buyOrder.remainingAmount < sellOrder.remainingAmount ? buyOrder.remainingAmount : sellOrder.remainingAmount;

        uint256 matchPrice = sellOrder.price;

        buyOrder.filledAmount += matchAmount;
        buyOrder.remainingAmount -= matchAmount;
        sellOrder.filledAmount += matchAmount;
        sellOrder.remainingAmount -= matchAmount;

        positions[buyOrder.eventId][buyOrder.outcomeId][buyOrder.user] += matchAmount;
        if (positions[sellOrder.eventId][sellOrder.outcomeId][sellOrder.user] >= matchAmount) {
            positions[sellOrder.eventId][sellOrder.outcomeId][sellOrder.user] -= matchAmount;
        } else {
            positions[sellOrder.eventId][sellOrder.outcomeId][sellOrder.user] = 0;
        }

        // Funds and fee settlement handled by funding module (fee rates and paths implemented by funding module)
        // IFundingPod(fundingPod).settleMatchedOrder(
        //     buyOrder.user,
        //     sellOrder.user,
        //     buyOrder.tokenAddress,
        //     matchAmount,
        //     buyOrder.eventId,
        //     buyOrder.outcomeId
        // );

        if (buyOrder.remainingAmount == 0) {
            buyOrder.status = OrderStatus.Filled;
            _removeFromOrderBook(buyOrderId);
        } else if (buyOrder.filledAmount > 0) {
            buyOrder.status = OrderStatus.Partial;
        }

        if (sellOrder.remainingAmount == 0) {
            sellOrder.status = OrderStatus.Filled;
            _removeFromOrderBook(sellOrderId);
        } else if (sellOrder.filledAmount > 0) {
            sellOrder.status = OrderStatus.Partial;
        }

        emit OrderMatched(buyOrderId, sellOrderId, buyOrder.eventId, buyOrder.outcomeId, matchPrice, matchAmount);
    }

    // ------------------------------------------------------------
    // Internal: orderbook operations
    // ------------------------------------------------------------
    function _addToOrderBook(uint256 orderId) internal {
        Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[order.outcomeId];

        if (order.side == OrderSide.Buy) {
            if (outcomeOrderBook.buyOrdersByPrice[order.price].length == 0) {
                _insertBuyPrice(outcomeOrderBook, order.price);
            }
            outcomeOrderBook.buyOrdersByPrice[order.price].push(orderId);
        } else {
            if (outcomeOrderBook.sellOrdersByPrice[order.price].length == 0) {
                _insertSellPrice(outcomeOrderBook, order.price);
            }
            outcomeOrderBook.sellOrdersByPrice[order.price].push(orderId);
        }
    }

    function _removeFromOrderBook(uint256 orderId) internal {
        Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[order.outcomeId];

        if (order.side == OrderSide.Buy) {
            uint256[] storage priceOrders = outcomeOrderBook.buyOrdersByPrice[order.price];
            _removeFromArray(priceOrders, orderId);
            if (priceOrders.length == 0) {
                _removeBuyPrice(outcomeOrderBook, order.price);
            }
        } else {
            uint256[] storage priceOrders = outcomeOrderBook.sellOrdersByPrice[order.price];
            _removeFromArray(priceOrders, orderId);
            if (priceOrders.length == 0) {
                _removeSellPrice(outcomeOrderBook, order.price);
            }
        }
    }

    function _insertBuyPrice(OutcomeOrderBook storage orderBook, uint256 price) internal {
        uint256 i = 0;
        while (i < orderBook.buyPriceLevels.length && orderBook.buyPriceLevels[i] > price) {
            i++;
        }
        if (i < orderBook.buyPriceLevels.length && orderBook.buyPriceLevels[i] == price) return;

        orderBook.buyPriceLevels.push(0);
        for (uint256 j = orderBook.buyPriceLevels.length - 1; j > i; j--) {
            orderBook.buyPriceLevels[j] = orderBook.buyPriceLevels[j - 1];
        }
        orderBook.buyPriceLevels[i] = price;
    }

    function _insertSellPrice(OutcomeOrderBook storage orderBook, uint256 price) internal {
        uint256 i = 0;
        while (i < orderBook.sellPriceLevels.length && orderBook.sellPriceLevels[i] < price) {
            i++;
        }
        if (i < orderBook.sellPriceLevels.length && orderBook.sellPriceLevels[i] == price) return;

        orderBook.sellPriceLevels.push(0);
        for (uint256 j = orderBook.sellPriceLevels.length - 1; j > i; j--) {
            orderBook.sellPriceLevels[j] = orderBook.sellPriceLevels[j - 1];
        }
        orderBook.sellPriceLevels[i] = price;
    }

    function _removeBuyPrice(OutcomeOrderBook storage orderBook, uint256 price) internal {
        for (uint256 i = 0; i < orderBook.buyPriceLevels.length; i++) {
            if (orderBook.buyPriceLevels[i] == price) {
                for (uint256 j = i; j < orderBook.buyPriceLevels.length - 1; j++) {
                    orderBook.buyPriceLevels[j] = orderBook.buyPriceLevels[j + 1];
                }
                orderBook.buyPriceLevels.pop();
                break;
            }
        }
    }

    function _removeSellPrice(OutcomeOrderBook storage orderBook, uint256 price) internal {
        for (uint256 i = 0; i < orderBook.sellPriceLevels.length; i++) {
            if (orderBook.sellPriceLevels[i] == price) {
                for (uint256 j = i; j < orderBook.sellPriceLevels.length - 1; j++) {
                    orderBook.sellPriceLevels[j] = orderBook.sellPriceLevels[j + 1];
                }
                orderBook.sellPriceLevels.pop();
                break;
            }
        }
    }

    function _removeFromArray(uint256[] storage array, uint256 value) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }

    function _totalAtPrice(uint256[] storage orderIds) internal view returns (uint256 total) {
        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage order = orders[orderIds[i]];
            if (order.status == OrderStatus.Pending || order.status == OrderStatus.Partial) {
                total += order.remainingAmount;
            }
        }
    }

    // ------------------------------------------------------------
    // Internal: cancel & settle orders
    // ------------------------------------------------------------
    function _cancelAllPendingOrders(uint256 eventId) internal {
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];

        for (uint256 i = 0; i < eventOrderBook.supportedOutcomes.length; i++) {
            uint256 outcomeId = eventOrderBook.supportedOutcomes[i];
            OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[outcomeId];
            _cancelMarketOrders(outcomeOrderBook);
        }
    }

    function _cancelMarketOrders(OutcomeOrderBook storage marketOrderBook) internal {
        for (uint256 i = 0; i < marketOrderBook.buyPriceLevels.length; i++) {
            uint256 price = marketOrderBook.buyPriceLevels[i];
            uint256[] storage ids = marketOrderBook.buyOrdersByPrice[price];
            for (uint256 j = 0; j < ids.length; j++) {
                Order storage order = orders[ids[j]];
                if (order.status == OrderStatus.Pending || order.status == OrderStatus.Partial) {
                    order.status = OrderStatus.Cancelled;
                    // 资金模块：批量撤单解锁资金（由资金模块实现）
                    // IFundingPod(fundingPod).unlockOnOrderCancelled(order.user, order.tokenAddress, order.remainingAmount, order.eventId, order.outcomeId);
                }
            }
        }

        for (uint256 i = 0; i < marketOrderBook.sellPriceLevels.length; i++) {
            uint256 price = marketOrderBook.sellPriceLevels[i];
            uint256[] storage ids = marketOrderBook.sellOrdersByPrice[price];
            for (uint256 j = 0; j < ids.length; j++) {
                Order storage order = orders[ids[j]];
                if (order.status == OrderStatus.Pending || order.status == OrderStatus.Partial) {
                    order.status = OrderStatus.Cancelled;
                    // Funding module: Batch unlock funds for cancelled orders (implemented by funding module)
                    // IFundingPod(fundingPod).unlockOnOrderCancelled(order.user, order.tokenAddress, order.remainingAmount, order.eventId, order.outcomeId);
                }
            }
        }
    }

    // Settle positions (placeholder, awaiting integration with funding module and user registry)
    function _settlePositions(
        uint256,
        /*eventId*/
        uint256 /*winningOutcomeId*/
    )
        internal {
        // TODO: integrate settlement with FundingPod balances when user registry is available.
    }
}
