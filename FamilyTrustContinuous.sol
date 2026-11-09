// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts@5.0.2/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/utils/SafeERC20.sol";

interface IFamilySafe {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}

/// @notice Sepolia classroom trust. No external keeper is installed by this contract.
/// @dev Non-upgradeable, direct deployment. Constructor sets the family atomically.
contract FamilyTrustContinuous {
    using SafeERC20 for IERC20;
    uint256 public constant UNIT = 1_000_000;
    uint256 public constant PERIOD_BUDGET = 1_500 * UNIT;
    uint256 public constant EMERGENCY_TARGET = 5_000 * UNIT;
    uint256 public constant DISCOUNT_BPS = 500;
    uint256 public constant EMERGENCY_TTL = 1 days;
    enum PauseReason { Setup, Manual, InsufficientFunds, None }
    enum EmergencyStatus { Pending, Paid, Rejected, Cancelled, Expired }
    enum LoanStatus { Pending, Accepted, Rejected, Cancelled, Expired, Repaid }
    struct Emergency {
        uint8 applicant;
        uint8 approvalMask;
        EmergencyStatus status;
        uint64 deadline;
        uint256 amount;
        string reason;
    }
    struct Loan {
        uint8 borrower;
        uint8 lender;
        LoanStatus status;
        uint256 createdPeriod;
        uint256 repayPeriod;
        uint256 principal;
        uint256 repayment;
    }

    // Persistent family ledger for continuous operation.
    IERC20 public token;
    address public funder;
    address public parentSafe;
    address[3] public beneficiaries;
    mapping(address => uint8) private childPlusOne;
    uint256 public periodDuration;
    uint256 public currentPeriod; // Last successfully settled period. Never increments merely with time.
    uint256 public nextDue;
    bool public paused;
    PauseReason public pauseReason;
    uint256 public operatingBalance;
    uint256 public emergencyBalance;
    uint256 public emergencyReserved;
    uint256 public totalClaimable;
    uint256 public discountAccumulated; // Informational; already belongs to operatingBalance.
    uint256 private entered;
    uint256[3] public claimable;
    uint256[3] public claimedThrough;
    mapping(uint256 => uint256[3]) private periodAllocation;
    mapping(uint256 => bool) public hasAllocationOverride;
    mapping(uint256 => uint256[3]) public advancedFace;
    mapping(uint256 => bool[3]) public advanceUsed;
    mapping(uint256 => uint256[3]) public repaymentReserved;
    mapping(uint256 => mapping(uint8 => mapping(uint8 => uint256))) public repaymentTo;
    mapping(uint256 => uint256[3]) private storedClaims;
    mapping(uint256 => bool[3]) public loanAcceptedInPeriod;
    uint256 public emergencyCount;
    uint256 public pendingEmergencyCount;
    mapping(uint256 => Emergency) private emergencies;
    mapping(uint8 => uint256) public pendingEmergencyId;
    uint256 public loanCount;
    mapping(uint256 => Loan) private loans;
    mapping(uint8 => uint256) public pendingLoanId;

    event Deposited(address indexed from, uint256 total, uint256 toOperating, uint256 toEmergency);
    event DonationSynced(uint256 total, uint256 toOperating, uint256 toEmergency);
    event Paused(PauseReason reason, uint256 nextPeriod);
    event Resumed(uint256 nextPeriod, uint256 nextDue);
    event PeriodSettled(uint256 indexed period, uint256 amount);
    event Claimed(address indexed beneficiary, uint256 amount);
    event AllocationChanged(uint256 indexed period, uint256[3] amounts);
    event AdvancePaid(address indexed beneficiary, uint256 indexed period, uint256 face, uint256 paid);
    event EmergencyRequested(uint256 indexed id, address indexed applicant, uint256 amount, string reason);
    event EmergencyApproved(uint256 indexed id, address indexed signer);
    event EmergencyResolved(uint256 indexed id, EmergencyStatus status);
    event LoanRequested(uint256 indexed id, address indexed borrower, address indexed lender, uint256 principal, uint256 repayment, uint256 repayPeriod);
    event LoanResolved(uint256 indexed id, LoanStatus status);
    event FundsRecovered(uint256 operating, uint256 emergency, address indexed safe);
    event DurationChanged(uint256 secondsPerPeriod);

    modifier onlySafe() { require(msg.sender == parentSafe, "Use parent Safe 2-of-2"); _; }
    modifier nonReentrant() { require(entered == 0, "Reentrant call"); entered = 1; _; entered = 0; }
    modifier running() { require(!paused, "Trust paused"); _; }

    constructor(address token_, address funder_, address safe_, address[3] memory children_)
    {
        require(token_.code.length > 0 && safe_.code.length > 0, "Token/Safe needs code");
        require(IERC20Metadata(token_).decimals() == 6, "Token needs 6 decimals");
        address[] memory owners = IFamilySafe(safe_).getOwners();
        require(IFamilySafe(safe_).getThreshold() == 2 && owners.length == 2, "Safe must be 2-of-2");
        require(funder_ != address(0) && (owners[0] == funder_ || owners[1] == funder_), "Funder must be a parent");
        token = IERC20(token_); funder = funder_; parentSafe = safe_;
        for (uint8 i; i < 3; ++i) {
            address c = children_[i];
            require(c != address(0) && c != address(this) && c != token_ && c != safe_, "Invalid child");
            require(c != owners[0] && c != owners[1] && childPlusOne[c] == 0, "Duplicate child or parent");
            beneficiaries[i] = c; childPlusOne[c] = i + 1;
        }
        periodDuration = 20; paused = true; pauseReason = PauseReason.Setup;
    }

    function contractVersion() external pure returns (uint256) { return 1; }
    function beneficiaryIndex(address who) public view returns (uint8) {
        require(childPlusOne[who] != 0, "Not a beneficiary"); return childPlusOne[who] - 1;
    }
    function allocation(uint256 period, uint256 index) public view returns (uint256) {
        require(period > 0 && index < 3, "Invalid period/index");
        return hasAllocationOverride[period] ? periodAllocation[period][index] : 500 * UNIT;
    }
    function periodClaims(uint256 period, uint256 index) public view returns (uint256) {
        require(index < 3, "Invalid index");
        return period <= claimedThrough[index] ? 0 : storedClaims[period][index];
    }
    function freeFutureAmount(uint256 period, uint8 index) public view returns (uint256) {
        require(period > currentPeriod && index < 3, "Not a future period");
        return allocation(period, index) - advancedFace[period][index] - repaymentReserved[period][index];
    }
    function nextPeriodCost() public view returns (uint256 cost) {
        uint256 p = currentPeriod + 1;
        for (uint8 i; i < 3; ++i) cost += allocation(p, i) - advancedFace[p][i];
    }
    function totalLiabilities() public view returns (uint256) {
        return operatingBalance + emergencyBalance + totalClaimable;
    }
    function accounting() external view returns (
        uint256 balance, uint256 operating, uint256 emergency, uint256 reservedEmergency,
        uint256 claims, uint256 unallocated, bool solvent
    ) {
        balance = token.balanceOf(address(this)); uint256 booked = totalLiabilities();
        return (balance, operatingBalance, emergencyBalance, emergencyReserved, totalClaimable,
            balance > booked ? balance - booked : 0, balance >= booked);
    }
    function _assertSolvent() internal view { require(token.balanceOf(address(this)) >= totalLiabilities(), "Insolvent"); }

    /// @notice Any amount; each NEW deposit first refills the emergency pool, capped at 5,000 FAM.
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount is zero");
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        require(token.balanceOf(address(this)) == beforeBalance + amount, "Exact transfer required");
        (uint256 op, uint256 em) = _bookDeposit(amount);
        emit Deposited(msg.sender, amount, op, em); _resumeAfterRefill(); _assertSolvent();
    }
    /// @notice Direct token transfers are not booked until this is called (also by resume/settlement).
    function syncDonation() external nonReentrant { _syncDonation(); _resumeAfterRefill(); _assertSolvent(); }
    function _bookDeposit(uint256 amount) internal returns (uint256 op, uint256 em) {
        uint256 gap = EMERGENCY_TARGET - emergencyBalance;
        em = amount < gap ? amount : gap; op = amount - em;
        emergencyBalance += em; operatingBalance += op;
    }
    function _syncDonation() internal {
        uint256 balance = token.balanceOf(address(this)); uint256 booked = totalLiabilities();
        require(balance >= booked, "Insolvent");
        if (balance > booked) {
            (uint256 op, uint256 em) = _bookDeposit(balance - booked);
            emit DonationSynced(balance - booked, op, em);
        }
    }
    function _resumeAfterRefill() internal {
        if (paused && pauseReason == PauseReason.InsufficientFunds && operatingBalance >= nextPeriodCost()) {
            paused = false; pauseReason = PauseReason.None; nextDue = block.timestamp + periodDuration;
            emit Resumed(currentPeriod + 1, nextDue);
        }
    }
    function pauseTrust() external onlySafe {
        require(!paused || pauseReason != PauseReason.Manual, "Already manually paused");
        paused = true; pauseReason = PauseReason.Manual; nextDue = 0;
        emit Paused(pauseReason, currentPeriod + 1);
    }
    /// @notice Setup: funder or Safe. Manual: only Safe. Low funds: anyone after enough funds arrive.
    function resumeTrust() external nonReentrant {
        require(paused, "Already running");
        if (pauseReason == PauseReason.Setup) require(msg.sender == funder || msg.sender == parentSafe, "Only funder/Safe can start");
        else if (pauseReason == PauseReason.Manual) require(msg.sender == parentSafe, "Use parent Safe 2-of-2");
        _syncDonation(); require(operatingBalance >= nextPeriodCost(), "Insufficient operating funds");
        paused = false; pauseReason = PauseReason.None; nextDue = block.timestamp + periodDuration;
        emit Resumed(currentPeriod + 1, nextDue); _assertSolvent();
    }
    function setPeriodDuration(uint256 seconds_) external onlySafe {
        require(paused && seconds_ >= 10 && seconds_ <= 365 days, "Pause; duration 10s to 365d");
        periodDuration = seconds_; emit DurationChanged(seconds_);
    }
    function setPeriodAllocation(uint256 period, uint256[3] calldata amounts) external onlySafe {
        require(period > currentPeriod, "Current/past period locked");
        require(amounts[0] + amounts[1] + amounts[2] == PERIOD_BUDGET, "Total must be 1500 FAM");
        for (uint8 i; i < 3; ++i) require(amounts[i] >= advancedFace[period][i] + repaymentReserved[period][i], "Below future commitment");
        periodAllocation[period] = amounts; hasAllocationOverride[period] = true;
        emit AllocationChanged(period, amounts);
    }

    /// @notice One elapsed period per call, never catches up missed wall-clock intervals.
    /// Insufficient funds pauses and RETURNS FALSE, so the pause is not reverted.
    function settleNextPeriod() external nonReentrant running returns (bool) {
        return _settleNext();
    }
    /// @notice One transaction credits the next period, then transfers all unpaid claims to all children.
    function distributeNextPeriod() external nonReentrant running returns (bool success) {
        success = _settleNext(); if (success) _payAll();
    }
    /// @notice Automation-compatible hooks. A keeper must be registered and funded separately.
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        bool due = !paused && block.timestamp >= nextDue;
        bool canRefill;
        if (paused && pauseReason == PauseReason.InsufficientFunds) {
            uint256 balance = token.balanceOf(address(this)); uint256 booked = totalLiabilities();
            uint256 extra = balance > booked ? balance - booked : 0;
            uint256 gap = EMERGENCY_TARGET - emergencyBalance;
            uint256 operatingExtra = extra > gap ? extra - gap : 0;
            canRefill = operatingBalance + operatingExtra >= nextPeriodCost();
        }
        return (due || canRefill, bytes(""));
    }
    function performUpkeep(bytes calldata) external nonReentrant {
        if (paused) {
            require(pauseReason == PauseReason.InsufficientFunds, "Trust paused");
            _syncDonation(); _resumeAfterRefill(); require(!paused, "Insufficient operating funds");
        } else if (_settleNext()) _payAll();
    }
    function _settleNext() internal returns (bool) {
        require(block.timestamp >= nextDue, "Period not due"); _syncDonation();
        uint256 cost = nextPeriodCost();
        if (operatingBalance < cost) {
            paused = true; pauseReason = PauseReason.InsufficientFunds; nextDue = 0;
            emit Paused(pauseReason, currentPeriod + 1); return false;
        }
        uint256 p = currentPeriod + 1;
        for (uint8 i; i < 3; ++i) {
            uint256 value = allocation(p, i) - advancedFace[p][i] - repaymentReserved[p][i];
            for (uint8 j; j < 3; ++j) value += repaymentTo[p][j][i];
            storedClaims[p][i] = value; claimable[i] += value;
        }
        operatingBalance -= cost; totalClaimable += cost;
        currentPeriod = p; nextDue = block.timestamp + periodDuration;
        emit PeriodSettled(p, cost); _assertSolvent(); return true;
    }
    function withdrawAll() external nonReentrant {
        uint8 i = beneficiaryIndex(msg.sender); require(claimable[i] > 0, "Nothing claimable"); _pay(i); _assertSolvent();
    }
    /// @notice Anyone may deliver claims to their fixed beneficiaries, including while paused.
    function payAllBeneficiaries() external nonReentrant { _payAll(); }
    function _payAll() internal {
        for (uint8 i; i < 3; ++i) if (claimable[i] > 0) _pay(i);
        _assertSolvent();
    }
    function _pay(uint8 i) internal {
        uint256 value = claimable[i]; claimable[i] = 0; totalClaimable -= value;
        claimedThrough[i] = currentPeriod;
        token.safeTransfer(beneficiaries[i], value); emit Claimed(beneficiaries[i], value);
    }

    function advanceNext(uint256 face) external nonReentrant running {
        uint8 i = beneficiaryIndex(msg.sender); uint256 p = currentPeriod + 1;
        require(currentPeriod > 0 && !advanceUsed[p][i], "No first advance or already used");
        require(face > 0 && face <= freeFutureAmount(p, i), "Insufficient future amount");
        uint256 paid = face * (10_000 - DISCOUNT_BPS) / 10_000;
        require(paid > 0 && operatingBalance >= paid, "Insufficient operating funds");
        advancedFace[p][i] += face; advanceUsed[p][i] = true;
        operatingBalance -= paid; discountAccumulated += face - paid;
        token.safeTransfer(msg.sender, paid); emit AdvancePaid(msg.sender, p, face, paid); _assertSolvent();
    }

    function requestEmergency(uint256 amount, string calldata reason) external running returns (uint256 id) {
        uint8 i = beneficiaryIndex(msg.sender); require(pendingEmergencyId[i] == 0, "Existing pending emergency");
        require(amount > 0 && amount <= emergencyBalance - emergencyReserved, "Emergency pool insufficient");
        require(bytes(reason).length > 0 && bytes(reason).length <= 160, "Reason 1 to 160 bytes");
        id = ++emergencyCount;
        emergencies[id] = Emergency(i, 0, EmergencyStatus.Pending, uint64(block.timestamp + EMERGENCY_TTL), amount, reason);
        pendingEmergencyId[i] = id; pendingEmergencyCount++; emergencyReserved += amount;
        emit EmergencyRequested(id, msg.sender, amount, reason);
    }
    function approveEmergency(uint256 id) external nonReentrant running {
        uint8 i = beneficiaryIndex(msg.sender); Emergency storage e = _pendingEmergency(id);
        require(block.timestamp < e.deadline, "Emergency expired");
        require(i != e.applicant, "Applicant cannot approve"); uint8 bit = uint8(1 << i);
        require(e.approvalMask & bit == 0, "Already approved"); e.approvalMask |= bit;
        emit EmergencyApproved(id, msg.sender);
        if (e.approvalMask == uint8(7 ^ (1 << e.applicant))) {
            _resolveEmergency(id, EmergencyStatus.Paid); emergencyBalance -= e.amount;
            token.safeTransfer(beneficiaries[e.applicant], e.amount); _assertSolvent();
        }
    }
    function rejectEmergency(uint256 id) external {
        uint8 i = beneficiaryIndex(msg.sender); require(i != _pendingEmergency(id).applicant, "Applicant should cancel");
        _resolveEmergency(id, EmergencyStatus.Rejected);
    }
    function cancelEmergency(uint256 id) external {
        uint8 i = beneficiaryIndex(msg.sender); require(i == _pendingEmergency(id).applicant, "Not applicant");
        _resolveEmergency(id, EmergencyStatus.Cancelled);
    }
    /// @notice Safe may cancel reservations while paused before recovering the emergency pool.
    function cancelEmergencyBySafe(uint256 id) external onlySafe {
        require(paused, "Pause first"); _pendingEmergency(id); _resolveEmergency(id, EmergencyStatus.Cancelled);
    }
    function expireEmergency(uint256 id) external {
        Emergency storage e = _pendingEmergency(id); require(block.timestamp >= e.deadline, "Not expired");
        _resolveEmergency(id, EmergencyStatus.Expired);
    }
    function getEmergency(uint256 id) external view returns (Emergency memory) {
        require(id > 0 && id <= emergencyCount, "Unknown emergency"); return emergencies[id];
    }
    function _pendingEmergency(uint256 id) internal view returns (Emergency storage e) {
        require(id > 0 && id <= emergencyCount, "Unknown emergency"); e = emergencies[id];
        require(e.status == EmergencyStatus.Pending, "Emergency resolved");
    }
    function _resolveEmergency(uint256 id, EmergencyStatus status) internal {
        Emergency storage e = emergencies[id]; e.status = status; emergencyReserved -= e.amount;
        pendingEmergencyId[e.applicant] = 0; pendingEmergencyCount--; emit EmergencyResolved(id, status);
    }

    function requestLoan(address lenderAddress, uint256 principal, uint256 repayment, uint256 repayPeriod)
        external running returns (uint256 id)
    {
        uint8 borrower = beneficiaryIndex(msg.sender); uint8 lender = beneficiaryIndex(lenderAddress);
        require(currentPeriod > 0 && borrower != lender, "No period or self lending");
        require(!loanAcceptedInPeriod[currentPeriod][borrower], "Already borrowed this period");
        require(repayPeriod >= currentPeriod + 2, "Repay from period after next");
        require(principal > 0 && repayment > principal, "Repayment must exceed principal");
        require(periodClaims(currentPeriod, lender) >= principal, "Lender current claim insufficient");
        require(freeFutureAmount(repayPeriod, borrower) >= repayment, "Repayment capacity insufficient");
        uint256 old = pendingLoanId[borrower];
        if (old != 0) { require(loans[old].createdPeriod != currentPeriod, "Existing pending loan"); loans[old].status = LoanStatus.Expired; emit LoanResolved(old, LoanStatus.Expired); }
        id = ++loanCount;
        loans[id] = Loan(borrower, lender, LoanStatus.Pending, currentPeriod, repayPeriod, principal, repayment);
        pendingLoanId[borrower] = id;
        emit LoanRequested(id, msg.sender, lenderAddress, principal, repayment, repayPeriod);
    }
    function acceptLoan(uint256 id) external nonReentrant running {
        uint8 i = beneficiaryIndex(msg.sender); Loan storage l = _pendingLoan(id);
        require(i == l.lender, "Only designated lender"); require(l.createdPeriod == currentPeriod, "Loan offer expired");
        require(!loanAcceptedInPeriod[currentPeriod][l.borrower], "Already borrowed this period");
        require(periodClaims(currentPeriod, i) >= l.principal, "Lender claim spent");
        require(freeFutureAmount(l.repayPeriod, l.borrower) >= l.repayment, "Future capacity changed");
        storedClaims[currentPeriod][i] -= l.principal; claimable[i] -= l.principal; totalClaimable -= l.principal;
        repaymentReserved[l.repayPeriod][l.borrower] += l.repayment;
        repaymentTo[l.repayPeriod][l.borrower][i] += l.repayment;
        loanAcceptedInPeriod[currentPeriod][l.borrower] = true;
        l.status = LoanStatus.Accepted; pendingLoanId[l.borrower] = 0;
        token.safeTransfer(beneficiaries[l.borrower], l.principal);
        emit LoanResolved(id, LoanStatus.Accepted); _assertSolvent();
    }
    function cancelLoan(uint256 id) external {
        uint8 i = beneficiaryIndex(msg.sender); Loan storage l = _pendingLoan(id);
        require(i == l.borrower || i == l.lender, "Not a loan party");
        l.status = i == l.borrower ? LoanStatus.Cancelled : LoanStatus.Rejected;
        pendingLoanId[l.borrower] = 0; emit LoanResolved(id, l.status);
    }
    function expireLoan(uint256 id) external {
        Loan storage l = _pendingLoan(id); require(l.createdPeriod != currentPeriod, "Not expired");
        l.status = LoanStatus.Expired; pendingLoanId[l.borrower] = 0; emit LoanResolved(id, l.status);
    }
    function getLoan(uint256 id) external view returns (Loan memory l) {
        require(id > 0 && id <= loanCount, "Unknown loan"); l = loans[id];
        if (l.status == LoanStatus.Pending && l.createdPeriod != currentPeriod) l.status = LoanStatus.Expired;
        else if (l.status == LoanStatus.Accepted && l.repayPeriod <= currentPeriod) l.status = LoanStatus.Repaid;
    }
    function _pendingLoan(uint256 id) internal view returns (Loan storage l) {
        require(id > 0 && id <= loanCount, "Unknown loan"); l = loans[id]; require(l.status == LoanStatus.Pending, "Loan not pending");
    }

    /// @notice Paused recovery sends ONLY unallocated operating funds to the Safe.
    /// Existing child claims always remain backed. Future unfunded allocations/loans wait for replenishment.
    function recoverOperating(uint256 amount) external nonReentrant onlySafe {
        require(paused, "Pause first"); _syncDonation();
        require(amount > 0 && amount <= operatingBalance, "Insufficient operating funds");
        operatingBalance -= amount; token.safeTransfer(parentSafe, amount);
        emit FundsRecovered(amount, 0, parentSafe); _assertSolvent();
    }
    /// @notice Includes emergency pool, but cannot seize pending reservations or accrued child claims.
    function recoverAllAvailable() external nonReentrant onlySafe {
        require(paused, "Pause first"); _syncDonation();
        require(pendingEmergencyCount == 0, "Resolve pending emergencies first");
        uint256 op = operatingBalance; uint256 em = emergencyBalance;
        require(op + em > 0, "Nothing recoverable"); operatingBalance = 0; emergencyBalance = 0;
        token.safeTransfer(parentSafe, op + em); emit FundsRecovered(op, em, parentSafe); _assertSolvent();
    }
}
