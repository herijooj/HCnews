#!/usr/bin/env bash

# Source common library if not already loaded
[[ -n "${_HCNEWS_COMMON_LOADED:-}" ]] || source "${HCNEWS_COMMON_PATH}common.sh" 2>/dev/null || source "${BASH_SOURCE%/*}/lib/common.sh"

# === Configuration ===

# --- API & Prompt Settings ---
# Use conditional readonly to prevent errors on re-sourcing
if [[ -z "${API_ENDPOINT:-}" ]]; then
    readonly API_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"
fi
if [[ -z "${MAX_OUTPUT_TOKENS:-}" ]]; then
    readonly MAX_OUTPUT_TOKENS=150
fi

# Use centralized cache directory from common.sh
# Cache configuration - handled by common.sh

# Use centralized TTL
CACHE_TTL_SECONDS="${HCNEWS_CACHE_TTL["futuro"]:-86400}"

# Parse cache args
hcnews_parse_args "$@"
_futuro_USE_CACHE=$_HCNEWS_USE_CACHE
_futuro_FORCE_REFRESH=$_HCNEWS_FORCE_REFRESH

# --- Dependencies Check ---
# Ensure curl and jq are installed
_futuro_DEPENDENCIES_MET=true
if ! command -v curl &> /dev/null; then
    _futuro_DEPENDENCIES_MET=false
fi
if ! command -v jq &> /dev/null; then
    _futuro_DEPENDENCIES_MET=false
fi

# === Functions ===

# Function: get_ai_fortune
function get_ai_fortune() {
    if [[ "$_futuro_DEPENDENCIES_MET" == false ]]; then
        echo "Error: Missing dependencies (curl or jq)." >&2
        return 1
    fi

    local date_format_local
    # Use cached date_format if available, otherwise fall back to date command
    local date_format_local; date_format_local=$(hcnews_get_date_format)
    local cache_file
    hcnews_set_cache_path cache_file "futuro" "$date_format_local"

    if [[ "${_HCNEWS_USE_CACHE:-true}" == true ]] && hcnews_check_cache "$cache_file" "$CACHE_TTL_SECONDS" "${_HCNEWS_FORCE_REFRESH:-false}"; then
        hcnews_read_cache "$cache_file"
        return 0
    fi

    # Using 30 words as the limit directly here
    local word_limit=30

    # Add date/day context for the AI model
    # Use cached values if available, otherwise fall back to date command
    local date_str
    local day_of_week_str
    if [[ -n "$day" && -n "$month" && -n "$year" ]]; then
        date_str="${day}/${month}/${year}"
    else
        date_str=$(date +"%d/%m/%Y")
    fi
    if [[ -n "$weekday" ]]; then
        # Convert weekday number to Portuguese day name
        case "$weekday" in
            1) day_of_week_str="Segunda-feira" ;;
            2) day_of_week_str="Terça-feira" ;;
            3) day_of_week_str="Quarta-feira" ;;
            4) day_of_week_str="Quinta-feira" ;;
            5) day_of_week_str="Sexta-feira" ;;
            6) day_of_week_str="Sábado" ;;
            7) day_of_week_str="Domingo" ;;
            *) day_of_week_str=$(date +"%A") ;;
        esac
    else
        day_of_week_str=$(date +"%A")
    fi
    local pre_prompt="Contexto: hoje é ${day_of_week_str}, ${date_str}." # Re-added date context

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
        echo "Error: GEMINI_API_KEY not found in environment." >&2
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
          "maxOutputTokens": $max_tokens,
          "thinkingConfig": {
            "thinkingBudget": 0
          }
          # Consider adding safety settings if needed, though less critical for creative tasks
          # "safetySettings": [ ... ]
        }
      }')

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create JSON payload using jq." >&2
        return 1
    fi

    # Make API Request
    http_response=$(curl -sf -4 --compressed -X POST "$full_api_url" \
         -H "Content-Type: application/json" \
         --data "$json_payload")
    curl_exit_code=$?

    # Handle curl errors
    if [[ $curl_exit_code -ne 0 ]]; then
      echo "Error: curl command failed with exit code $curl_exit_code." >&2
      return 1
    fi

    # SINGLE jq call to extract everything we need: error, finishReason, and text
    local parsed_response
    parsed_response=$(echo "$http_response" | jq -r '
      {
        error: (.error.message // ""),
        finish_reason: (.candidates[0].finishReason // "REASON_UNKNOWN"),
        text: (.candidates[0].content.parts[0].text // "")
      } | "\(.error)|\(.finish_reason)|\(.text)"
    ')
    
    local api_error finish_reason fortune_raw
    IFS='|' read -r api_error finish_reason fortune_raw <<< "$parsed_response"

    # Handle API errors
    if [[ -n "$api_error" ]]; then
        echo "Error: API returned an error message: $api_error" >&2
        if [[ "$api_error" == *"API key not valid"* ]]; then
            echo "Hint: Check if GEMINI_API_KEY is correct and enabled." >&2
        fi
        return 1
    fi

    # Check finish reason
    if [[ "$finish_reason" != "STOP" && "$finish_reason" != "MAX_TOKENS" ]]; then
        echo "Warning: Generation finished unexpectedly. Reason: $finish_reason" >&2
        if [[ -z "$fortune_raw" && "$finish_reason" == "SAFETY" ]]; then
           echo "Error: Content blocked due to safety settings." >&2
           return 1
        elif [[ -z "$fortune_raw" ]]; then
           echo "Error: Could not extract fortune text. Reason: $finish_reason." >&2
           return 1
        fi
    fi

    if [[ -z "$fortune_raw" ]]; then
      echo "Error: Could not extract fortune text from API response." >&2
      return 1
    fi

    # Output raw fortune text if successful
    if [[ "${_HCNEWS_USE_CACHE:-true}" == true ]]; then
        hcnews_write_cache "$cache_file" "$fortune_raw"
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
    fortune_raw=$(get_ai_fortune 2>/dev/null)
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

# Function to display help message
function show_help() {
    echo "Usage: ./futuro.sh [options]"
    echo "Generates a futuristic prediction using a generative AI model."
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message and exit."
    echo "  --no-cache   Do not use cached data; fetch a new prediction."
    echo "  --force        Force a refresh of the cache, even if it is recent."
}

# Function to parse command-line arguments
function get_arguments() {
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                show_help
                exit 0
                ;;
            --no-cache)
                _futuro_USE_CACHE=false
                ;;
            --force)
                _futuro_FORCE_REFRESH=true
                ;;
            *)
                # Allow unrecognized arguments to be handled by other parts of the script if necessary
                # or show an error.
                # echo "Warning: Unrecognized argument '$1'" >&2
                ;;
        esac
    done
}

# -------------------------------- Running the script --------------------------------

# If the script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command-line arguments
    get_arguments "$@"

    # Check if API key exists
    if [[ -z "$GEMINI_API_KEY" ]]; then
      echo "Error: GEMINI_API_KEY not found in environment." >&2
      echo "Please set GEMINI_API_KEY as an environment variable." >&2
      exit 1
    fi

    # Call the main function to generate and print the section
    write_ai_fortune
    # The exit status of the script will depend on write_ai_fortune
fi

# Optional: If sourced, the functions get_ai_fortune and write_ai_fortune
# are now available to the sourcing script.
