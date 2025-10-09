import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toUtf8Bytes } from "ethers";

export default buildModule("ALFAForgeModule", (m) => {
  // Параметры — чтобы не хардкодить адреса
  const ALFAKey_ADDRESS       = m.getParameter<string>("ALFAKey_ADDRESS");
  const ALFAReferral_ADDRESS  = m.getParameter<string>("ALFAReferral_ADDRESS");
  const ALFAVault_ADDRESS     = m.getParameter<string>("ALFAVault_ADDRESS");
  const BURN_ACCOUNT          = m.getParameter<string>("BURN_ACCOUNT");
  const TEAM_ACCOUNT          = m.getParameter<string>("TEAM_ACCOUNT");
  const USDT_ADDRESS          = m.getParameter<string>("USDT_ADDRESS");
  const USDC_ADDRESS          = m.getParameter<string>("USDC_ADDRESS");

  // Подцепляем уже существующие контракты
  const alfaKey      = m.contractAt("ALFAKey", ALFAKey_ADDRESS);
  const alfaReferral = m.contractAt("ALFAReferral", ALFAReferral_ADDRESS);
  const alfaVault    = m.contractAt("ALFAVault", ALFAVault_ADDRESS);

  // Деплоим ALFAForge
  const forge = m.contract("ALFAForge", [
    ALFAKey_ADDRESS,            // address ALFAKey
    BURN_ACCOUNT,       // address burn
    ALFAReferral_ADDRESS,       // address referral
    ALFAVault_ADDRESS           // address vault
  ]);

  // // Пост-инициализация
  // m.call(forge, "setTeamAccount", [TEAM_ACCOUNT], { id: "forgeSetTeamAccount" });
  // m.call(forge, "addToken", [USDT_ADDRESS], { id: "forgeAddTokenUSDT" });
  // m.call(forge, "addToken", [USDC_ADDRESS], { id: "forgeAddTokenUSDC" });
  //
  // // Роли OZ: bytes32 public constant = keccak256("…") — считаем локально, чтобы не делать on-chain чтения
  // const BURNER_ROLE    = keccak256(toUtf8Bytes("BURNER_ROLE"));
  // const MINTER_ROLE    = keccak256(toUtf8Bytes("MINTER_ROLE"));
  // const CONNECTOR_ROLE = keccak256(toUtf8Bytes("CONNECTOR_ROLE"));
  //
  // // Выдаём права новому ALFAForge
  // m.call(alfaKey, "grantRole", [BURNER_ROLE, forge], { id: "alfaKeyGrantBurnerToForge" });
  // m.call(alfaKey, "grantRole", [MINTER_ROLE, forge], { id: "alfaKeyGrantMinterToForge" });
  // m.call(alfaReferral, "grantRole", [CONNECTOR_ROLE, forge], { id: "alfaReferralGrantConnectorToForge" });

  return { forge };
});