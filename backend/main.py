from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from mangum import Mangum
from openai import AsyncOpenAI
import os
import logging
import json
import asyncio
import nltk
from nltk.tokenize import sent_tokenize, word_tokenize
from nltk.corpus import stopwords
import string

nltk.data.path.append('/var/task/nltk_data')

logging.basicConfig(level=logging.INFO, force=True)
logger = logging.getLogger(__name__)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    # Update <BASE_URL> with your unique domain name
    allow_origins=["<BASE_URL>"],
    allow_credentials=True,
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)

class BlendRequest(BaseModel):
    prompt: str

async def query_grok(prompt: str, api_key: str) -> str:
    try:
        client = AsyncOpenAI(api_key=api_key, base_url="https://api.x.ai/v1")
        completion = await client.chat.completions.create(
            model="grok-2-latest",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=500,
        )
        return completion.choices[0].message.content.strip()
    except Exception as e:
        logger.error(f"Grok API error: {str(e)}")
        return f"Error querying Grok: {str(e)}"

async def query_openai(prompt: str, api_key: str) -> str:
    try:
        client = AsyncOpenAI(api_key=api_key, base_url="https://api.openai.com/v1")
        completion = await client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=500,
        )
        return completion.choices[0].message.content.strip()
    except Exception as e:
        logger.error(f"OpenAI API error: {str(e)}")
        return f"Error querying OpenAI: {str(e)}"

def preprocess_text(text: str, prompt: str) -> dict:
    text_clean = text.replace(f"{prompt}: ", "").strip()
    sentences = sent_tokenize(text_clean)
    stop_words = set(stopwords.words('english') + list(string.punctuation))
    words = [w.lower() for w in word_tokenize(text_clean) if w.lower() not in stop_words]
    return {"sentences": sentences, "key_words": set(words), "original": text_clean}

def calculate_overlap(key_words1: set, key_words2: set) -> float:
    intersection = len(key_words1 & key_words2)
    union = len(key_words1 | key_words2)
    return intersection / union if union > 0 else 0

def sentence_similarity(sent1: str, sent2: str) -> float:
    stop_words = set(stopwords.words('english') + list(string.punctuation))
    words1 = set(w.lower() for w in word_tokenize(sent1) if w.lower() not in stop_words)
    words2 = set(w.lower() for w in word_tokenize(sent2) if w.lower() not in stop_words)
    if not words1 or not words2:
        return 0.0
    intersection = len(words1 & words2)
    union = len(words1 | words2)
    return intersection / union

def aggregate_responses(grok_response: str, openai_response: str, prompt: str) -> str:
    if "Error querying" in grok_response and "Error querying" in openai_response:
        return "Unable to generate a blended response due to API errors."
    elif "Error querying" in grok_response:
        return openai_response
    elif "Error querying" in openai_response:
        return grok_response

    grok_data = preprocess_text(grok_response, prompt)
    openai_data = preprocess_text(openai_response, prompt)

    overlap = calculate_overlap(grok_data["key_words"], openai_data["key_words"])
    logger.info(f"Overall overlap score: {overlap}")

    grok_sentences = grok_data["sentences"]
    openai_sentences = openai_data["sentences"]

    # Track key concepts to avoid repetition
    used_sentences = set()
    used_keywords = set()

    blended_sentences = []

    # Interleave sentences, starting with Grok
    for g_sent in grok_sentences:
        if g_sent.lower() not in used_sentences:
            g_words = set(w.lower() for w in word_tokenize(g_sent) if w.lower() not in stopwords.words('english'))
            blended_sentences.append(g_sent)
            used_sentences.add(g_sent.lower())
            used_keywords.update(g_words)

            # Find and weave in a matching OpenAI sentence
            best_match = None
            best_score = 0.6  # Higher threshold for tighter integration
            for o_sent in openai_sentences:
                if o_sent.lower() in used_sentences:
                    continue
                score = sentence_similarity(g_sent, o_sent)
                o_words = set(w.lower() for w in word_tokenize(o_sent) if w.lower() not in stopwords.words('english'))
                # Check if it adds new info (not just repeating keywords)
                new_info = len(o_words - used_keywords) > len(o_words) * 0.3  # At least 30% new keywords
                if score > best_score and new_info:
                    best_match = o_sent
                    best_score = score
            
            if best_match:
                blended_sentences.append(best_match)
                used_sentences.add(best_match.lower())
                used_keywords.update(o_words)

    # Add remaining unique OpenAI sentences with new info
    for o_sent in openai_sentences:
        if o_sent.lower() not in used_sentences:
            o_words = set(w.lower() for w in word_tokenize(o_sent) if w.lower() not in stopwords.words('english'))
            new_info = len(o_words - used_keywords) > len(o_words) * 0.3
            if new_info:
                blended_sentences.append(o_sent)
                used_sentences.add(o_sent.lower())
                used_keywords.update(o_words)

    # Join into a cohesive response
    blended = " ".join(blended_sentences).strip()
    blended = blended.replace("..", ".").replace("  ", " ")
    if not blended.endswith("."):
        blended += "."
    
    return blended

@app.post("/blend")
async def blend(request: BlendRequest):
    logger.info(f"Received request with prompt: {request.prompt}")
    if not request.prompt.strip():
        raise HTTPException(status_code=422, detail="Field 'prompt' cannot be empty")
    grok_api_key = os.getenv("GROK_API_KEY")
    openai_api_key = os.getenv("OPENAI_API_KEY")
    if not grok_api_key or not openai_api_key:
        raise HTTPException(status_code=500, detail="API keys not configured")
    grok_task = query_grok(request.prompt, grok_api_key)
    openai_task = query_openai(request.prompt, openai_api_key)
    grok_response, openai_response = await asyncio.gather(grok_task, openai_task)
    blended = aggregate_responses(grok_response, openai_response, request.prompt)
    logger.info(f"Returning blended response: {blended}")
    return {
        "blended": blended,
        "grok_response": grok_response,
        "openai_response": openai_response
    }

handler = Mangum(app)

def lambda_handler(event, context):
    logger.info("Lambda event: " + json.dumps(event))
    response = handler(event, context)
    if "headers" not in response:
        response["headers"] = {}
        # Update <BASE_URL> with your unique domain name
        response["headers"]["Access-Control-Allow-Origin"] = "<BASE_URL>"
        response["headers"]["Access-Control-Allow-Headers"] = "Content-Type,Authorization"
    return response