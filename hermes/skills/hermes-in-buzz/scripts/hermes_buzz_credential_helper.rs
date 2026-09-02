//! Portable Buzz credential helper for the hermes-in-buzz skill.
//!
//! Private keys are read only from stdin and never accepted in argv.

use std::io::{self, BufRead};

use buzz_sdk::nip_oa;
use nostr::{Keys, PublicKey, ToBech32};

fn read_secret(label: &str) -> String {
    let mut secret = String::new();
    if io::stdin().lock().read_line(&mut secret).is_err() {
        eprintln!("failed to read {label} from stdin");
        std::process::exit(1);
    }
    let secret = secret.trim().to_owned();
    if secret.is_empty() {
        eprintln!("empty {label}");
        std::process::exit(1);
    }
    secret
}

fn main() {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("public") => {
            let secret = read_secret("agent secret");
            let keys = Keys::parse(&secret).unwrap_or_else(|_| {
                eprintln!("invalid agent nsec/private key");
                std::process::exit(1);
            });
            let public = keys.public_key();
            let npub = public.to_bech32().unwrap_or_else(|_| {
                eprintln!("failed to encode agent npub");
                std::process::exit(1);
            });
            println!("hex={}", public.to_hex());
            println!("npub={npub}");
        }
        Some("auth-tag") => {
            let agent_hex = args.next().unwrap_or_else(|| {
                eprintln!("usage: hermes-buzz-credential-helper auth-tag <agent-pubkey-hex> [conditions]");
                std::process::exit(2);
            });
            let conditions = args.next().unwrap_or_default();
            let owner_secret = read_secret("owner secret");
            let owner_keys = Keys::parse(&owner_secret).unwrap_or_else(|_| {
                eprintln!("invalid owner nsec/private key");
                std::process::exit(1);
            });
            let agent_public = PublicKey::from_hex(&agent_hex).unwrap_or_else(|_| {
                eprintln!("invalid agent public key");
                std::process::exit(1);
            });
            let tag = nip_oa::compute_auth_tag(&owner_keys, &agent_public, &conditions)
                .unwrap_or_else(|_| {
                    eprintln!("failed to compute owner attestation");
                    std::process::exit(1);
                });
            println!("{tag}");
        }
        Some("self-test") => {
            let owner = Keys::generate();
            let agent = Keys::generate();
            let result = nip_oa::compute_auth_tag(&owner, &agent.public_key(), "");
            match result {
                Ok(tag) if tag.starts_with("[\"auth\"") => println!("ok"),
                _ => {
                    eprintln!("self-test failed");
                    std::process::exit(1);
                }
            }
        }
        _ => {
            eprintln!("usage: hermes-buzz-credential-helper <public|auth-tag|self-test> ...");
            std::process::exit(2);
        }
    }
}
