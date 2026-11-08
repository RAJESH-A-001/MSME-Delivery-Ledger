# MSME Delivery & Acceptance Ledger

A decentralized delivery tracking and acceptance platform for Micro, Small and Medium Enterprises (MSMEs). Businesses can create orders, record dispatches, track deliveries, confirm receipts, and accept or reject goods — all backed by tamper-resistant Ethereum blockchain records.

---

## Table of Contents

- [Project Objective](#project-objective)
- [Technology Stack](#technology-stack)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
  - [Frontend](#frontend)
  - [Backend](#backend)
  - [Blockchain](#blockchain)
- [Environment Variables](#environment-variables)
- [Contributing](#contributing)

---

## Project Objective

Traditional MSME supply chains rely on paper-based or siloed digital records that are prone to disputes, loss, and manipulation. This platform replaces them with:

- **On-chain delivery receipts** — immutable records of dispatch and acceptance
- **Multi-party confirmation** — buyer, seller, and logistics provider each sign off
- **Dispute resolution** — timestamped, auditable acceptance/rejection events
- **Off-chain enrichment** — rich metadata stored in Supabase, indexed for fast queries

---

## Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Frontend** | React 18 + Vite | UI framework and build tool |
| | Tailwind CSS v4 | Utility-first styling |
| | React Router v6 | Client-side routing |
| | Ethers.js v6 | Ethereum wallet integration |
| **Backend** | Python 3.11+ | Server runtime |
| | FastAPI | REST API framework |
| | Uvicorn | ASGI server |
| | Supabase Python SDK | Database & auth client |
| **Database** | Supabase PostgreSQL | Persistent off-chain data |
| | Supabase Auth | User authentication |
| | Supabase Storage | Document & file storage |
| **Blockchain** | Solidity ^0.8.19 | Smart contract language |
| | Hardhat | Ethereum development environment |
| | Ethereum / MetaMask | Network & wallet |
| **DevOps** | Git + GitHub | Version control |

---

## Project Structure

```
MSME-Delivery-Ledger/
│
├── frontend/               # React + Vite application
│   ├── src/
│   │   ├── App.jsx
│   │   └── main.jsx
│   ├── index.html
│   ├── vite.config.js
│   └── package.json
│
├── backend/                # FastAPI application
│   ├── main.py             # App entry point + /health endpoint
│   ├── requirements.txt    # Pinned Python dependencies
│   └── venv/               # Python virtual environment (git-ignored)
│
├── blockchain/             # Hardhat project
│   ├── contracts/          # Solidity smart contracts
│   ├── scripts/            # Deployment scripts
│   ├── test/               # Contract tests
│   ├── hardhat.config.js
│   └── package.json
│
├── docs/                   # Architecture diagrams & documentation
│
├── .gitignore
├── .env.example            # Safe environment variable template
└── README.md
```

---

## Quick Start

### Prerequisites

- Node.js >= 18
- Python >= 3.11
- MetaMask browser extension
- Supabase account (for database milestones)

---

### Frontend

```bash
cd frontend
npm install
npm run dev
# → http://localhost:5173
```

### Backend

```bash
cd backend

# Windows
python -m venv venv
venv\Scripts\activate

# macOS / Linux
python3 -m venv venv
source venv/bin/activate

pip install -r requirements.txt
uvicorn main:app --reload
# → http://localhost:8000
# → Swagger UI: http://localhost:8000/docs
```

### Blockchain

```bash
cd blockchain
npm install
npx hardhat compile

# Start local node (optional)
npx hardhat node

# Run tests
npx hardhat test
```

---

## Environment Variables

Copy `.env.example` to `.env` and fill in your values. **Never commit `.env`.**

```bash
cp .env.example .env
```

---

## Contributing

This project is developed milestone by milestone. See `docs/` for architecture decisions and milestone plans.

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m 'feat: add your feature'`
4. Push to the branch: `git push origin feature/your-feature`
5. Open a Pull Request

---

*Built for MSMEs. Powered by Ethereum.*
