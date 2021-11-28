// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

contract Shop {
    struct Product {
        uint256 productId;
        string contentCId;
        string detailsCId;
        string licenseHash;
        string lockedLicense;
        uint256 price;
        uint256 stock;
        uint256[2] rating; // [0] = number of ratings, [1] = sum of ratings
        uint256 salesCount;
        bool isAvailable;
    }

    struct Sale {
        uint256 saleId;
        address buyer;
        string publicKey;
        uint256 productId;
        uint256 amount;
        uint256 saleDeadline;
        bytes32[2] unlockedLicense;
        uint256 rating;
        SaleStatus status;
    }

    enum SaleStatus {
        Requested,
        Refunded,
        Completed,
        Rated
    }

    address public guild;
    address public owner;
    uint256 public shopBalance;
    string public detailsCId;
    string public shopName;

    uint256 public productsCount = 0;
    uint256 public salesCount = 0;

    Product[] public products;

    mapping(uint256 => Sale) public sales;
    uint256[] public openSaleIds;
    uint256[] public closeSaleIds;

    mapping(uint256 => uint256) openSaleIdToIndex;

    modifier onlyGuild() {
        require(msg.sender == guild);
        _;
    }

    event ProductCreated(string shopName, uint256 productId);

    constructor(
        address _owner,
        string memory _shopName,
        string memory _detailsCId
    ) {
        guild = msg.sender;
        owner = _owner;
        detailsCId = _detailsCId;
        shopName = _shopName;
    }

    function addProduct(
        string memory _contentCId,
        string memory _detailsCId,
        string memory _licenseHash,
        string memory _lockedLicense,
        uint256 _price,
        uint256 _stock
    ) public onlyGuild {
        products.push(
            Product({
                productId: productsCount,
                contentCId: _contentCId,
                detailsCId: _detailsCId,
                licenseHash: _licenseHash,
                lockedLicense: _lockedLicense,
                price: _price,
                stock: _stock,
                salesCount: 0,
                rating: [uint256(0), uint256(0)],
                isAvailable: true
            })
        );
        productsCount++;

        emit ProductCreated(shopName, productsCount - 1);
    }

    function requestSale(
        address _buyer,
        uint256 _productId,
        string memory _publicKey
    ) public payable onlyGuild {
        require(_productId <= productsCount);
        require(products[_productId].salesCount < products[_productId].stock);
        require(products[_productId].isAvailable);
        require(products[_productId].price <= msg.value);

        sales[salesCount] = Sale({
            saleId: salesCount,
            buyer: _buyer,
            publicKey: _publicKey,
            productId: _productId,
            amount: msg.value,
            saleDeadline: block.timestamp + 10000,
            unlockedLicense: [bytes32(0), bytes32(0)],
            rating: 0,
            status: SaleStatus.Requested
        });
        openSaleIds.push(salesCount);
        openSaleIdToIndex[salesCount] = openSaleIds.length - 1;
        salesCount++;
    }

    function getRefund(uint256 _saleId) public payable onlyGuild {
        require(sales[_saleId].status == SaleStatus.Requested);
        require(block.timestamp > sales[_saleId].saleDeadline);

        sales[_saleId].status = SaleStatus.Refunded;
        closeSaleIds.push(_saleId);
        openSaleIds[openSaleIdToIndex[_saleId]] = openSaleIds[
            openSaleIds.length - 1
        ];
        openSaleIds.pop();
        delete openSaleIdToIndex[_saleId];

        (bool sent, ) = sales[_saleId].buyer.call{value: sales[_saleId].amount}(
            ""
        );
        require(sent, "Could not send refund");
    }

    function closeSale(uint256 _saleId, bytes32[2] memory _unlockedLicense)
        public
        onlyGuild
    {
        require(sales[_saleId].status == SaleStatus.Requested);
        require(sales[_saleId].saleDeadline > block.timestamp);

        sales[_saleId].unlockedLicense = _unlockedLicense;
        sales[_saleId].status = SaleStatus.Completed;

        shopBalance += sales[_saleId].amount;
        closeSaleIds.push(_saleId);

        openSaleIds[openSaleIdToIndex[_saleId]] = openSaleIds[
            openSaleIds.length - 1
        ];
        openSaleIds.pop();
        delete openSaleIdToIndex[_saleId];
    }

    function addRating(uint256 _saleId, uint256 _rating) public onlyGuild {
        require(sales[_saleId].status == SaleStatus.Completed);
        sales[_saleId].rating = _rating;
        sales[_saleId].status = SaleStatus.Rated;
        products[sales[_saleId].productId].rating[0]++;
        products[sales[_saleId].productId].rating[1] += _rating;
    }

    function shelfProduct(uint256 _productId) public onlyGuild {
        products[_productId].isAvailable = false;
    }

    function changePrice(uint256 _productId, uint256 _price) public onlyGuild {
        products[_productId].price = _price;
    }

    function changeStock(uint256 _productId, uint256 _stock) public onlyGuild {
        products[_productId].stock = _stock;
    }

    function withdraw(uint256 _amount) public payable onlyGuild {
        require(shopBalance > _amount);
        shopBalance -= _amount;
        (bool sent, ) = owner.call{value: _amount}("");
        require(sent, "Error on withdraw");
    }
}
