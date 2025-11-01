#!/usr/bin/env python3
import sys
import json

# Konstanta pro hledanou aplikaci
TARGET_APP_ID = "Vivaldi-flatpak"
# Konstanta pro návratovou hodnotu při nalezení aplikace uvnitř workspace
APP_FOUND = "FOUND"

def find_workspace(node):
    """
    Rekurzivně prochází sway/i3 tree JSON a vrací název workspace,
    ve kterém se nachází hledaná aplikace.
    """
    
    # 1. Zpracování polí (např. 'nodes' nebo 'floating_nodes')
    if isinstance(node, list):
        for item in node:
            result = find_workspace(item)
            # Pokud se podařilo najít aplikaci, vrátíme výsledek
            if result:
                return result
    
    # 2. Zpracování objektů (dict - kontejner, okno, workspace)
    elif isinstance(node, dict):
        
        # A) Kontrola, zda je to cílová aplikace
        if node.get("app_id") == TARGET_APP_ID:
            # Vrátíme speciální marker pro nadřazený uzel
            return APP_FOUND
        
        # B) Kontrola, zda je to workspace – potenciální rodič
        if node.get("type") == "workspace":
            workspace_name = node.get("name")
            
            # Projdeme rekurzivně obsah tohoto workspace (nodes i floating_nodes)
            for key in ["nodes", "floating_nodes"]:
                if key in node:
                    result = find_workspace(node[key])
                    
                    # Pokud se uvnitř našla aplikace, vracíme název workspace
                    if result == APP_FOUND:
                        return workspace_name
        
        # C) Procházení dál do jiných kontejnerů (mimo workspace)
        for key in ["nodes", "floating_nodes"]:
            if key in node:
                result = find_workspace(node[key])
                if result:
                    return result
    
    # Nic nebylo nalezeno v tomto podstromu
    return None

def main():
    """Hlavní funkce pro spuštění a zpracování vstupu."""
    # Načti JSON ze standardního vstupu
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        print("Chyba: Neplatný JSON vstup. Ujistěte se, že 'swaymsg -t get_tree' vrací JSON.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Chyba při čtení vstupu: {e}", file=sys.stderr)
        sys.exit(1)

    # Spusť hledání od kořene stromu
    result = find_workspace(data)

    if result and result != APP_FOUND:
        # Vypíše název workspace, např. '1'
        print(result)
        sys.exit(0)
    else:
        # Hledaná aplikace nebyla nalezena
        sys.exit(1)

if __name__ == "__main__":
    main()
