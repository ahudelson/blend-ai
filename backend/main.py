from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from mangum import Mangum
from openai import AsyncOpenAI
import os
import logging
import json
import asyncio

logging.basicConfig(level=logging.INFO, force=True)
logger = logging.getLogger(__name__)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    # Update <BASE_URL> with your unique domain name
    allow_origins=["<BASE_URL>"],
    allow_credentials=True,
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["Content-Type,Authorization"],
)

class BlendRequest(BaseModel):
    prompt: str

async def query_grok(prompt: str, api_key: str) -> str:
    try:
        client = AsyncOpenAI(
            api_key=api_key,
            base_url="https://api.x.ai/v1",
        )
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
        client = AsyncOpenAI(
            api_key=api_key,
            base_url="https://api.openai.com/v1",
        )
        completion = await client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=500,
        )
        return completion.choices[0].message.content.strip()
    except Exception as e:
        logger.error(f"OpenAI API error: {str(e)}")
        return f"Error querying OpenAI: {str(e)}"

def aggregate_responses(grok_response: str, openai_response: str, prompt: str) -> str:
    if "Error querying" in grok_response and "Error querying" in openai_response:
        return "Unable to generate a blended response due to API errors."
    elif "Error querying" in grok_response:
        return openai_response
    elif "Error querying" in openai_response:
        return grok_response

    grok_clean = grok_response.replace(f"{prompt}: ", "").strip()
    openai_clean = openai_response.replace(f"{prompt}: ", "").strip()

    if grok_clean.lower() == openai_clean.lower():
        return grok_clean
    else:
        blended = f"{grok_clean} Additionally, {openai_clean.lower()[0:1]}{openai_clean[1:]}"
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
    return handler(event, context)