// Create a wallet object that is used to store the private client side state

/* Data Structure

commitment = hash(SCOPE, depositor, value, parent, hash(nullifier, secret))

this: {
    scopes: [0XBOW_ETH_ETHEREUM_POOL]
    accounts: {
        0XBOW_ETH_ETHEREUM_POOL: Accounts {}
    }
}

Account: {
    depositAddress: string
    initial_deposit: Deposit {
        amount: number
        secret: string
        nullifier: string
        commitment: string
    }
    withdrawals: Withdrawal[{
        amount: number
        secret: string
        nullifier: string
        commitment: string
        parent: string
    }],
    initialCommitment: string
    latestCommitment: string
    balance: number
    ragequit: Ragequit {
        amount: number
        secret: string
        nullifier: string
        parent: string
    }
}

accounts are keyed by SCOPE & initial deposit commitment

this.accounts = {
    SCOPE: {
        [deposit.commitment]: Account{} 
    }
}

Plan is to have a "history" object of all the deposits, withdrawals, and ragequits
- the event history can be exported and replayed on a new wallet instance to recreate the state of the wallet
*/

// Storage: log all actions & replay to get synchronized with latest state
// - user clicks deposit -> generate deposit & save in data structure on success -> export
// - user clicks withdraw -> generate withdraw (& new deposit) & save in data structure on success -> export
// need _deposit, _withdraw, _ragequit function which update internal state
// deposit/withdraw/ragequit is public API to log new event and call _deposit etc to update internal state

const Wallet = function (initial_scope) {
    this.scopes = [initial_scope]
    this.accounts = {} 
    this.accounts[initial_scope] = {}
    this.SCOPE = initial_scope

    this.createAccount = function (deposit) {
        const account = {
            initialDeposit: deposit,
            initialCommitment: deposit.commitment,
            depositAddress: deposit.depositAddress,
            latestCommitment: deposit.commitment,
            balance: deposit.amount,
            withdrawals: [],
            ragequit: null
        }
        return account
    }
    return this
}

Wallet.prototype.hash = function (inputsArray) {
    // return Poseidon.hash(inputsArray)
    return "0xhash"
}

// Public function for saving a new deposit event - logs it and updates internal state
Wallet.prototype.deposit = function(depositorAddress, amount, secret, nullifier) {
    const depositEvent = {
        scope: this.SCOPE,
        type: "deposit",
        depositorAddress,
        amount,
        secret,
        nullifier
    }
    this.history.push(depositEvent)
    this._deposit(depositorAddress, amount, secret, nullifier)
}

// Internal function for updating internal state after a deposit event
Wallet.prototype._deposit = function(depositorAddress, amount, secret, nullifier) {
    const parent = null // deposits have no parents
    const commitment = this.generateCommitment(depositorAddress, amount, parent, secret, nullifier)
    const deposit = {
        depositAddress: 
        amount,
        secret,
        nullifier,
        commitment
    }

    const account = this.createAccount(deposit)

    // use initialCommitment as the unique key for the account
    this.accounts[this.SCOPE][account.initialCommitment] = account
}

// Public method for generating a deposit secret/nullifier & commitment
Wallet.prototype.generateDeposit = function(depositorAddress, amount, key) {
    const secret = this.hash(key) // TODO: generate secret based on user key (or random)
    const nullifier = this.hash(key) // TODO: generate nullifier based on user key (or random)
    const parent = null // deposits have no parents
    const commitment = this.generateCommitment(depositorAddress, amount, parent, secret, nullifier)
    return {
        depositorAddress,
        amount,
        secret, 
        nullifier, 
        commitment 
    }
}

// Public helper function for generating commitments
Wallet.prototype.generateCommitment = function(depositorAddress, amount, parent, secret, nullifier) {
    return this.hash([this.SCOPE, depositorAddress, amount, parent, this.hash([nullifier, secret])])
}

// Public function for saving a new withdrawal event - log it and update internal state
Wallet.prototype.withdraw = function (parent, amount, secret, nullifier) {
    const withdrawEvent = {
        scope: this.SCOPE,
        type: "withdrawal",
        parent,
        amount,
        secret,
        nullifier,
    }
    this.history.push(withdrawEvent)
    this._withdraw(parent, amount, secret, nullifier)
}

// Public method for generating a withdrawal secret/nullifier & commitment
// TODO - update with private inputs needed to build a proof for the withdrawal
Wallet.prototype.generateWithdrawal = function(parent, amount, parent, key) {
    const account = this.accounts[this.SCOPE][parent]
    const newSecret = this.hash(key) // TODO: generate secret based on user key (or random)
    const newNullifier = this.hash(key) // TODO: generate nullifier based on user key (or random)
    const newCommitment = this.generateCommitment(account.depositAddress, amount, parent, newSecret, newNullifier)

    return {
        amount,
        secret: newSecret,
        nullifier: newNullifier,
        commitment: newCommitment,
        parent
    }
}

// Internal function for updating internal state after a withdrawal function
Wallet.prototype._withdraw = function(initialCommitment, amount, parent, secret, nullifier) {
    const account = this.accounts[this.SCOPE][initialCommitment]
    const commitment = this.generateCommitment(account.depositAddress, amount, parent, secret, nullifier)
    const withdrawal = {
        amount,
        secret,
        nullifier,
        commitment,
        parent
    }
    account.withdrawals.push(withdrawal)
    account.latestCommitment = commitment
    account.balance -= amount
}

// Public method for generating a ragequit
Wallet.prototype.generateRagequit = function(amount, parent, key) {
    const account = this.accounts[this.SCOPE][parent]
    const secret = this.hash(key) // TODO: generate secret based on user key (or random)
    const nullifier = this.hash(key) // TODO: generate nullifier based on user key (or random)
    const commitment = this.generateCommitment(account.depositAddress, amount, parent, secret, nullifier)
    return {
        amount,
        secret,
        nullifier,
        commitment,
        parent
    }
} 

Wallet.prototype.ragequit = function (amount, parent) {
    const ragequitEvent = {
        scope: this.SCOPE,
        type: "ragequit",
        amount,
        parent
    }
    this.history.push(ragequitEvent)
    this._ragequit(amount, parent)
}

Wallet.prototype._ragequit = function (parent, amount) {
    const account = this.accounts[this.SCOPE][parent]
    account.ragequit = {
        amount,
        parent: account.latestCommitment
    }
    account.balance -= amount
} 

Wallet.prototype.updateScope = function (scope) {
    this.SCOPE = scope
}

Wallet.prototype.addScope = function (scope) {
    this.scopes.push(scope)
    this.accounts[scope] = []
}

Wallet.prototype.exportHistory = function () {
    return this.history
}

/* import a series of events of potentially different scopes
Event examples:
  deposit: { scope: "0XBOW_ETH_ETHEREUM_POOL" type: "deposit", depositorAddress, amount, secret, nullifier }}
  withdrawal: { scope: "0XBOW_ETH_ETHEREUM_POOL", type: "withdrawal", amount, secret, nullifier, parent }}
  ragequit: { scope: "0XBOW_ETH_ETHEREUM_POOL", type: "ragequit", parent }}
*/
Wallet.prototype.importHistory = function (history) {
    for (const event of history) {
        if (event.SCOPE !== this.SCOPE) {
            if (this.scopes.includes(event.SCOPE)) {
                this.updateScope(event.SCOPE)
            } else {
                this.addScope(event.SCOPE)
                this.updateScope(event.SCOPE)
            }
        }
        switch (event.type) {
            case "deposit":
                this.deposit(event.depositorAddress, event.amount, event.secret, event.nullifier)
                break
            case "withdraw":
                this.withdraw(event.amount, event.secret, event.nullifier, event.parent)
                break
            case "ragequit":
                this.ragequit(event.parent)
                break
        }
    }
}

const wallet = new Wallet(["0XBOW_ETH_ETHEREUM_POOL"])

wallet.deposit("0x123", 100, "secret", "nullifier")

console.log(JSON.stringify(wallet, null, 2))
