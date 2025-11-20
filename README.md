# 🎓 Education Grants Tracker Smart Contract

A transparent and accountable system for managing educational grants on the Stacks blockchain.

## 📚 Overview

The Education Grants Tracker is a smart contract that enables:
- 💰 Creation and management of educational grants
- 🎯 Milestone-based fund disbursement
- ✅ Committee voting on milestone completion
- 📊 Transparent tracking of fund allocation

## 🔑 Key Features

1. **Grant Creation**
   - Administrators can create grants with specified recipients and total amounts
   - Each grant can have multiple milestones

2. **Milestone Management**
   - Define milestones with specific amounts and due dates
   - Recipients must submit completion proof
   - Committee members vote on milestone completion

3. **Fund Distribution**
   - Automatic fund release upon sufficient approval votes
   - Transparent tracking of remaining grant amounts

## 📋 Functions

### Administrative Functions
- `create-grant`: Create a new educational grant
- `add-milestone`: Add milestone to existing grant
- `update-approval-threshold`: Modify required approval votes
- `release-milestone-funds`: Release approved milestone funds

### User Functions
- `submit-milestone-completion`: Submit milestone completion proof
- `vote-on-milestone`: Vote on milestone completion
- `get-grant`: View grant details
- `get-milestone`: View milestone details
- `get-grant-milestones`: View all milestones for a grant

## 🚀 Getting Started

1. Deploy the contract using Clarinet
2. Set up initial grant parameters
3. Add committee members
4. Create milestones
5. Begin tracking and disbursement

## ⚖️ Requirements

- Stacks 2.0 compatible wallet
- Clarinet for development and testing
```
