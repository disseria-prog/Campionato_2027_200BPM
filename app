import streamlit as st
import pandas as pd
import json
import os

st.set_page_config(page_title="Campionato Sociale Triathlon 2027", layout="wide")

# Path File Config & Data
PATH_ATLETI = "config/atleti_2027.json"
PATH_PUNTEGGI = "config/punteggi_2027.json"
PATH_GARE = "data/gare_2027.json"

os.makedirs("config", exist_ok=True)
os.makedirs("data", exist_ok=True)

# Helper caricamento/salvataggio JSON
def load_json(path, default):
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return default

def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

# Inizializzazione dati
atleti_db = load_json(PATH_ATLETI, [])
punteggi_config = load_json(PATH_PUNTEGGI, {})
gare_db = load_json(PATH_GARE, [])

# Sidebar Navigation
st.sidebar.title("🏆 Triathlon Team 2027")
menu = st.sidebar.radio("Seleziona Funzione", ["📊 Classifiche Generali", "📥 Importa & Valida Gara", "⚙️ Configurazione Inizio Anno"])

# -----------------------------------------------------------------------------
# MENU 1: CLASSIFICHE GENERALI
# -----------------------------------------------------------------------------
if menu == "📊 Classifiche Generali":
    st.header("Classifica Campionato Sociale 2027")
    
    if not gare_db:
        st.info("Nessuna gara registrata per la stagione 2027.")
    else:
        # Costruzione tabella classifica da gare_db
        records = []
        for atleta in atleti_db:
            cognome = atleta["cognome"]
            cat = atleta["categoria"]
            punti_gare = []
            
            for gara in gare_db:
                res = next((item for item in gara["risultati"] if item["cognome"].upper() == cognome.upper()), None)
                if res:
                    punti_gare.append(res["punti_totali"])
            
            punti_totali = sum(punti_gare)
            num_gare = len(punti_gare)
            media = punti_totali / num_gare if num_gare > 0 else 0
            
            records.append({
                "Atleta": cognome,
                "Categoria": cat,
                "Gare Disputate": num_gare,
                "Punti Totali": punti_totali,
                "Media Punti": round(media, 2)
            })
        
        df_rank = pd.DataFrame(records).sort_values(by="Punti Totali", ascending=False).reset_index(drop=True)
        df_rank.index += 1
        
        st.dataframe(df_rank, use_container_width=True)

# -----------------------------------------------------------------------------
# MENU 2: IMPORTAZIONE E VALIDAZIONE GARA (PROCEDURA POST-GARA)
# -----------------------------------------------------------------------------
elif menu == "📥 Importa & Valida Gara":
    st.header("Importazione e Validazione Risultati Gara")
    
    with st.form("form_gara"):
        col1, col2, col3 = st.columns(3)
        nome_gara = col1.text_input("Nome Gara (es. Peschiera Olim 2027)")
        data_gara = col2.date_input("Data Gara")
        tipo_gara = col3.selectbox("Tipologia Gara", ["Sprint", "Atipico", "Olimpico", "Medio", "Superlungo"])
        
        uploaded_file = st.file_uploader("Carica file ENDU (CSV o Excel)", type=["csv", "xlsx", "xls"])
        btn_elabora = st.form_submit_button("Elabora e Calcola Punteggi Provvisori")

    if btn_elabora and uploaded_file and nome_gara:
        # Caricamento file grezzo
        if uploaded_file.name.endswith(".csv"):
            df_endu = pd.read_csv(uploaded_file)
        else:
            df_endu = pd.read_excel(uploaded_file)
            
        # Normalizzazione colonne ENDU (adatta se necessario i nomi delle colonne)
        df_endu.columns = [c.strip().lower() for c in df_endu.columns]
        
        # Identificazione Cognome (flessibile)
        col_cognome = next((c for c in df_endu.columns if "cognome" in c or "name" in c or "atleta" in c), None)
        
        if not col_cognome:
            st.error("Impossibile trovare la colonna Atleta/Cognome nel file caricato.")
        else:
            # Filtro tesserati
            tesserati_cognomi = [a["cognome"].upper() for a in atleti_db]
            df_filtered = df_endu[df_endu[col_cognome].astype(str).str.upper().isin(tesserati_cognomi)].copy()
            
            # Calcolo Punti Base secondo regolamento
            punti_base = punteggi_config.get("basi", {}).get(tipo_gara, 10)
            
            calcolati = []
            for _, row in df_filtered.iterrows():
                cog = row[col_cognome].strip().upper()
                
                # Qui aggiungi la logica specifica per calcolare nuoto/bici se le colonne sono presenti nel file ENDU
                # In caso contrario, imposta i punti base + valore predefinito
                punti_nuoto = 10.0
                punti_bici = 10.0
                punti_corsa = 10.0
                punti_tot = punti_base + punti_nuoto + punti_bici + punti_corsa
                
                calcolati.append({
                    "cognome": cog,
                    "punti_base": punti_base,
                    "punti_nuoto": punti_nuoto,
                    "punti_bici": punti_bici,
                    "punti_corsa": punti_corsa,
                    "punti_totali": punti_tot,
                    "note_override": ""
                })
            
            st.session_state["tmp_gara_results"] = pd.DataFrame(calcolati)
            st.session_state["tmp_gara_meta"] = {"nome": nome_gara, "data": str(data_gara), "tipo": tipo_gara}

    # SCHERMATA DI VALIDAZIONE E OVERRIDE MANUALE
    if "tmp_gara_results" in st.session_state:
        st.subheader(f"Validazione Punteggi: {st.session_state['tmp_gara_meta']['nome']}")
        st.warning("⚠️ **Verifica i punteggi calcolati**. Puoi modificare manualmente i valori nelle celle (es. correzioni ad hoc, bonus o anomalie della gara) prima di salvare.")
        
        # Tabella modificabile interattiva
        edited_df = st.data_editor(
            st.session_state["tmp_gara_results"],
            column_config={
                "punti_totali": st.column_config.NumberColumn("Punti Totali Assegnati", help="Modifica qui se la gara ha un punteggio speciale"),
                "note_override": st.column_config.TextColumn("Motivo eventuale modifica")
            },
            num_rows="dynamic",
            use_container_width=True
        )
        
        if st.button("💾 CONFERMA E PUBBLICA RISULTATI GARA"):
            nuova_gara = {
                "metadata": st.session_state["tmp_gara_meta"],
                "risultati": edited_df.to_dict(orient="records")
            }
            gare_db.append(nuova_gara)
            save_json(PATH_GARE, gare_db)
            
            st.success("Gara validata e salvata con successo! Classifiche aggiornate.")
            del st.session_state["tmp_gara_results"]
            st.rerun()

# -----------------------------------------------------------------------------
# MENU 3: CONFIGURAZIONE ANAGRAFICA & REGOLE
# -----------------------------------------------------------------------------
elif menu == "⚙️ Configurazione Inizio Anno":
    st.header("Gestione Anagrafica Atleti 2027")
    
    df_atleti = pd.DataFrame(atleti_db)
    edited_atleti = st.data_editor(df_atleti, num_rows="dynamic", use_container_width=True)
    
    if st.button("Salva Anagrafica"):
        save_json(PATH_ATLETI, edited_atleti.to_dict(orient="records"))
        st.success("Anagrafica atleti aggiornata!")
