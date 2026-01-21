# 👗 Digital Clothing Rental Platform

A decentralized NFT clothing rental platform built on Stacks blockchain that allows users to rent digital outfits for metaverse events with time-based expiration.

## 🚀 Features

- **👕 Create Digital Outfits**: Upload and list your NFT clothing items for rent
- **⏰ Time-Based Rentals**: Rent outfits with automatic expiration using hour-based duration
- **💰 Automated Payments**: Smart contract handles payments between renters and owners
- **📊 Rental Analytics**: Track rental history and revenue for each outfit
- **🔒 Secure Ownership**: Immutable ownership records and rental agreements
- **💸 Platform Fees**: Configurable platform fee system for sustainability

## 📋 Contract Functions

### Public Functions

#### `create-outfit`
Create a new digital outfit NFT for rental.
```clarity
(create-outfit name description image-uri rental-price-per-hour category)
```

#### `rent-outfit`
Rent an available outfit for a specified duration.
```clarity
(rent-outfit outfit-id duration-hours)
```

#### `return-outfit`
Return a rented outfit before expiration.
```clarity
(return-outfit rental-id)
```

#### `force-return-expired-outfit`
Force return an expired rental (can be called by anyone).
```clarity
(force-return-expired-outfit rental-id)
```

#### `update-outfit-price`
Update the rental price of your outfit.
```clarity
(update-outfit-price outfit-id new-price)
```

#### `toggle-outfit-availability`
Enable/disable your outfit for rental.
```clarity
(toggle-outfit-availability outfit-id)
```

### Read-Only Functions

#### `get-outfit`
Get outfit details by ID.
```clarity
(get-outfit outfit-id)
```

#### `get-rental`
Get rental details by ID.
```clarity
(get-rental rental-id)
```

#### `get-user-active-rentals`
Get all active rentals for a user.
```clarity
(get-user-active-rentals user-principal)
```

#### `calculate-rental-cost`
Calculate total cost for renting an outfit.
```clarity
(calculate-rental-cost outfit-id duration-hours)
```

#### `is-rental-expired`
Check if a rental has expired.
```clarity
(is-rental-expired rental-id)
```

#### `get-rental-time-remaining`
Get remaining hours for an active rental.
```clarity
(get-rental-time-remaining rental-id)
```

## 🎯 Usage Examples

### Creating an Outfit
```clarity
(contract-call? .Digital-cloth-renting create-outfit 
  u"Cyberpunk Jacket"
  u"Futuristic neon jacket perfect for metaverse events"
  u"https://example.com/jacket.png"
  u100  ;; 100 STX per block
  u"Outerwear"
)
```

### Renting an Outfit
```clarity
;; Rent outfit #1 for 24 hours
(contract-call? .Digital-cloth-renting rent-outfit u1 u24)
```

### Checking Rental Cost
```clarity
(contract-call? .Digital-cloth-renting calculate-rental-cost u1 u24)
;; Returns: {total-cost: u2400, platform-fee: u120, owner-payment: u2280}
```

## 💡 Key Concepts

- **Hour-Based Duration**: Rentals are measured in hours for easy understanding
- **Automatic Expiration**: Outfits become available again after rental period ends  
- **Platform Fee**: Default 5% fee goes to contract owner (configurable)
- **Force Return**: Anyone can return expired rentals to make outfits available
- **Time Simulation**: Use `advance-time` function for testing time-based features

## 🔧 Development Setup

1. **Install Clarinet**
   ```bash
   npm install -g @hirosystems/clarinet-cli
   ```

2. **Initialize Project**
   ```bash
   clarinet new digital-clothing-rental
   cd digital-clothing-rental
   ```

3. **Deploy Contract**
   ```bash
   clarinet deploy
   ```

4. **Run Tests**
   ```bash
   clarinet test
   ```

## 📊 Error Codes

| Code | Description |
|------|-------------|
| u100 | Owner only operation |
| u101 | Outfit/Rental not found |
| u102 | Outfit already rented |
| u103 | Outfit not currently rented |
| u104 | Insufficient payment |
| u105 | Rental has expired |
| u106 | Unauthorized operation |
| u107 | Invalid duration |
| u108 | Outfit not available |

## 🎮 Metaverse Integration

This contract is designed to integrate with:
- **Virtual Worlds**: Decentraland, Sandbox, VRChat
- **Gaming Platforms**: Blockchain-based games
- **Social Platforms**: Virtual events and meetups
- **NFT Marketplaces**: OpenSea, Magic Eden

## 🛡️ Security Features

- ✅ Owner-only functions for outfit management
- ✅ Automatic payment distribution
- ✅ Rental expiration enforcement
- ✅ Principal validation for all operations
- ✅ STX balance verification before rentals

## 📈 Business Model

1. **Outfit Owners**: Earn passive income from rentals
2. **Renters**: Access premium outfits without buying
3. **Platform**: Sustainable revenue through transaction fees
4. **Events**: Special outfit collections for metaverse events

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License.

---

**Ready to revolutionize digital fashion? Start renting today! 🌟**
