#!/usr/bin/env bash

# Source tokens file for API keys
source tokens.sh

# === Configuration ===

# --- API & Prompt Settings ---
readonly API_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent"
#readonly MAX_WORDS=25
readonly MAX_OUTPUT_TOKENS=150

# --- Cache Settings ---
_futuro_SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
_futuro_CACHE_DIR="$(dirname "$_futuro_SCRIPT_DIR")/data/cache/futuro"

# --- Dependencies Check ---
# Ensure curl and jq are installed
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed." >&2
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# === Functions ===

# Function: get_ai_fortune
function get_ai_fortune() {
    local local_use_cache=true
    local local_force_refresh=false

    # Check for global flags from hcnews.sh if this script is sourced
    if [[ -n "${hc_no_cache+x}" && "$hc_no_cache" == true ]]; then
        local_use_cache=false
    fi
    if [[ -n "${hc_force_refresh+x}" && "$hc_force_refresh" == true ]]; then
        local_force_refresh=true
    fi

    local date_format
    date_format=$(date +"%Y%m%d")
    mkdir -p "$_futuro_CACHE_DIR" # Ensure cache directory exists
    local cache_file="${_futuro_CACHE_DIR}/${date_format}_fortune.cache"

    if [[ "$local_use_cache" == true && "$local_force_refresh" == false && -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi

    # Using 30 words as the limit directly here
    local word_limit=30

    # Add date/day context for the AI model
    local date=$(date +"%d/%m/%Y")
    local day_of_week=$(date +"%A")
    local pre_prompt="Contexto: hoje é ${day_of_week}, ${date}." # Re-added date context

    # --- Improved Prompts ---
    # Instructions added: Respond ONLY with the phrase, no date/day mentions.
    local prompts=(
      "Escreva uma previsão de biscoito da sorte *absurdamente* engraçada em menos de ${word_limit} palavras. Responda *apenas* com a frase da previsão, sem saudações ou menção de data/dia."
      "Revele um futuro ridiculamente improvável e específico. Seja breve (máximo ${word_limit} palavras). Responda *apenas* com a frase da previsão, sem saudações ou menção de data/dia."
      "Descreva uma cena curtíssima (${word_limit} palavras) que viole as leis da física ou da lógica de forma surreal e poética. Responda *apenas* com a frase da previsão, sem saudações ou menção de data/dia."
      "Compartilhe uma 'sabedoria' profundamente esquisita e inesperada em até ${word_limit} palavras. Que soe quase verdadeiro. Responda *apenas* com a frase da previsão, sem saudações ou menção de data/dia."
      "Faça uma previsão *sarcástica* e irreverente. Máximo ${word_limit} palavras, por favor. Responda *apenas* com a frase da previsão, sem saudações ou menção de data/dia."
      "Um oráculo digital com defeito prevê seu futuro imediato em ${word_limit} palavras ou menos. Qual a previsão? Responda *apenas* com a frase da previsão, sem saudações ou menção de data/dia."
      "Imagine o conselho mais bizarro que uma IA poderia dar. Curto (${word_limit} palavras). Responda *apenas* com a frase da previsão, sem saudações ou menção de data/dia."
    )
    local num_prompts=${#prompts[@]} # Get the number of prompts dynamically
    local temps=(0.4 0.6 0.8 1.0)
    local random_prompt_index=$((RANDOM % num_prompts)) # Use dynamic count
    local random_temp_index=$((RANDOM % 4))
    # Combine date context with the chosen prompt
    local prompt_text="${pre_prompt} ${prompts[$random_prompt_index]}"
    TEMPERATURE="${temps[$random_temp_index]}"
    local json_payload http_response curl_exit_code api_error fortune_raw

    # Check for API key
    if [[ -z "$GEMINI_API_KEY" ]]; then
        echo "Error: GEMINI_API_KEY not found in tokens.sh file." >&2
        return 1
    fi

    local full_api_url="${API_ENDPOINT}?key=${GEMINI_API_KEY}"

    # Build JSON Payload safely using jq
    json_payload=$(jq -n \
      --arg prompt "$prompt_text" \
      --argjson temp "$TEMPERATURE" \
      --argjson max_tokens "$MAX_OUTPUT_TOKENS" \
      '{
        "contents": [{
          "parts": [{
            "text": $prompt
          }]
        }],
        "generationConfig": {
          "temperature": $temp,
          "maxOutputTokens": $max_tokens
          # Consider adding safety settings if needed, though less critical for creative tasks
          # "safetySettings": [ ... ]
        }
      }')

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create JSON payload using jq." >&2
        return 1
    fi

    # Make API Request
    http_response=$(curl -sf -X POST "$full_api_url" \
         -H "Content-Type: application/json" \
         --data "$json_payload")
    curl_exit_code=$?

    # Handle curl errors
    if [[ $curl_exit_code -ne 0 ]]; then
      echo "Error: curl command failed with exit code $curl_exit_code." >&2
      # Attempt to extract API error from potential JSON error response curl might still output
      api_error=$(echo "$http_response" | jq -r '.error.message // ""' 2>/dev/null)
      if [[ -n "$api_error" ]]; then
         echo "API Error Hint: $api_error" >&2
      else
         echo "Check network connection, API key validity, endpoint correctness (${API_ENDPOINT}), or firewall issues." >&2
      fi
      return 1
    fi

    # Handle API errors within the JSON response
    # Use jq's // operator for safer default value handling
    api_error=$(echo "$http_response" | jq -r '.error.message // ""' 2>/dev/null)
    if [[ -n "$api_error" ]]; then
        echo "Error: API returned an error message: $api_error" >&2
        # echo "Full response: $http_response" >&2 # Uncomment for debugging
        # Check for specific error codes or messages if needed
        if [[ "$api_error" == *"API key not valid"* ]]; then
            echo "Hint: Check if GEMINI_API_KEY in tokens.sh is correct and enabled." >&2
        fi
        return 1
    fi

     # Check if candidates array exists and has content before extracting text
    fortune_raw=$(echo "$http_response" | jq -r '.candidates[0].content.parts[0].text // ""')

    # Add an explicit check for safety blocks / finishReason
    local finish_reason
    finish_reason=$(echo "$http_response" | jq -r '.candidates[0].finishReason // "REASON_UNKNOWN"')
    if [[ "$finish_reason" != "STOP" && "$finish_reason" != "MAX_TOKENS" ]]; then
        echo "Warning: Generation finished unexpectedly. Reason: $finish_reason" >&2
        # Check if content is empty due to safety filters
        if [[ -z "$fortune_raw" && "$finish_reason" == "SAFETY" ]]; then
           echo "Error: Content blocked due to safety settings." >&2
           # echo "Full response: $http_response" >&2 # Uncomment for debugging
           return 1
        elif [[ -z "$fortune_raw" ]]; then
           echo "Error: Could not extract fortune text. Reason: $finish_reason. Response might be empty or malformed." >&2
           # echo "Full response: $http_response" >&2 # Uncomment for debugging
           return 1
        fi
        # Decide if you want to proceed even if finishReason isn't STOP/MAX_TOKENS but text exists
        # For now, we proceed if text was extracted.
    fi


    if [[ -z "$fortune_raw" ]]; then
      echo "Error: Could not extract fortune text from API response (it might be empty or missing)." >&2
      # echo "Full response: $http_response" >&2 # Uncomment for debugging
      return 1
    fi

    # Output raw fortune text if successful
    if [[ "$local_use_cache" == true && $? -eq 0 && -n "$fortune_raw" ]]; then
        echo "$fortune_raw" > "$cache_file"
    fi
    echo "$fortune_raw"
    return 0
}

# Function: write_ai_fortune
# Calls get_ai_fortune, checks for success, cleans the result,
# and prints it in the final formatted way.
function write_ai_fortune() {
    local fortune_raw fortune_clean

    # Get the fortune text; capture stdout, check return status
    fortune_raw=$(get_ai_fortune)
    local get_status=$?

    # If getting the fortune failed, display funny error message in Portuguese
    if [[ $get_status -ne 0 ]]; then
        # Array of funny error messages in Portuguese
        local error_messages=(
            "🤖 *ERRO CÓSMICO:* O Heric acabou com os tokens da API! Agora a IA está em greve até o próximo pagamento! 💸"
            "🔮 *FALHA NA MATRIX:* Tokens esgotados! Heric esqueceu de alimentar a IA com créditos novos... que fome! 🍽️"
            "📛 *PANE NO SISTEMA:* Acabaram os tokens! A IA implora: 'Heric, não me abandone na pobreza digital!' 😭"
            "⚠️ *PREVISÃO INTERROMPIDA:* A bola de cristal digital ficou sem bateria... ou o Heric ficou sem tokens. Provavelmente a segunda opção! 🔋"
            "🐒 *MACAQUINHOS NO SERVIDOR:* Tentamos consultar o futuro, mas o Heric gastou todos os tokens em previsões sobre quando vai ganhar na loteria! 🎰"
            "🚫 *PORTAL FECHADO:* A IA vidente entrou em modo de economia de energia (tokens). Culpa do Heric! 📉"
        )
        local num_messages=${#error_messages[@]}
        local random_index=$((RANDOM % num_messages))

        echo "${error_messages[$random_index]}"
        echo "" # Add a blank line after the section
        exit 1 # Exit the script since we can't proceed
    fi

    # Simple cleanup: remove potential leading/trailing quotes, asterisks, and whitespace
    fortune_clean=$(echo "$fortune_raw" | sed -e 's/^[[:space:]"*]*//' -e 's/[[:space:]"*]*$//')

    # Print the formatted section
    echo "🔮 *Previsão do Futuro: (via Gemini)*"
    echo "- 📜 ${fortune_clean}"
    echo "" # Add a blank line after the section
}

# -------------------------------- Running the script --------------------------------

# If the script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check if API key exists in tokens.sh
    if [[ -z "$GEMINI_API_KEY" ]]; then
      echo "Error: GEMINI_API_KEY not found in tokens.sh file." >&2
      echo "Please add your Gemini API key to tokens.sh" >&2
      exit 1
    fi

    # Call the main function to generate and print the section
    write_ai_fortune
    # The exit status of the script will depend on write_ai_fortune
fi

# Optional: If sourced, the functions get_ai_fortune and write_ai_fortune
# are now available to the sourcing script.