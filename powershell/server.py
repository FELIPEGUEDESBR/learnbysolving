from fastapi import FastAPI
from pydantic import BaseModel
from diffusers import StableDiffusionPipeline
import torch
import os
from io import BytesIO
from fastapi.responses import Response

app = FastAPI()

MODEL_MAP = {
    "sd-v1-4": "CompVis/stable-diffusion-v1-4",
    "sd-v1-5": "runwayml/stable-diffusion-v1-5",
    # You can add more later
}

current_model_name = None

pipe = None
def load_pipeline(model_key: str):
    global pipe, current_model_name
    
    if model_key not in MODEL_MAP:
        raise ValueError(f"Unsupported model: {model_key}")
        
    if current_model_name == model_key:
        return # already loaded
        
    model_id = MODEL_MAP[model_key]
    print(f"Loading model: {model_id}")
    
    new_pipe = StableDiffusionPipeline.from_pretrained(
        model_id,
        torch_dtype=torch_dtype,
        use_auth_token=os.environ.get("HF_TOKEN")
    ).to(device)
    
    new_pipe.enable_attention_slicing()
    
    pipe = new_pipe
    current_model_name = model_key
class Txt2ImgRequest(BaseModel):
    prompt: str
    steps: int = 25
    guidance_scale: float = 7.5
    width: int = 512
    height: int = 512
    model: str = "sd-v1-5"

# --------------------------
# Universal GPU/CPU detection
# --------------------------
if torch.cuda.is_available():
    device = "cuda"
    torch_dtype = torch.float16
else:
    device = "cpu"
    torch_dtype = torch.float32

pipe = StableDiffusionPipeline.from_pretrained(
    "runwayml/stable-diffusion-v1-5",
    torch_dtype=torch_dtype,
    use_auth_token=os.environ.get("HF_TOKEN")
).to(device)

# SAFE ON ALL MACHINES
pipe.enable_attention_slicing()

try:
    pipe.enable_xformers_memory_efficient_attention()
except:
    pass

@app.post("/txt2img")
def txt2img(req: Txt2ImgRequest):
    try:
        load_pipeline(req.model)
        
        image = pipe(
            req.prompt,
            num_inference_steps=req.steps,
            guidance_scale=req.guidance_scale,
            width=req.width,
            height=req.height
        ).images[0]

        buf = BytesIO()
        image.save(buf, format="PNG")
        return Response(buf.getvalue(), media_type="image/png")

    except Exception as e:
        print("Error generating image:", e)
        raise e