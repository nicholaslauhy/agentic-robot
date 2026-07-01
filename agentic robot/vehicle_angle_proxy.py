"""FastAPI route for secure vehicle-angle validation.

Add ``app.include_router(router)`` to the FastAPI backend already serving port
8000, then set OPENAI_API_KEY in that server's environment. The key never
travels to or ships inside the iOS app.
"""

import base64
import json
import os
import urllib.error
import urllib.request

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel


router = APIRouter()
OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"
MAX_IMAGE_BYTES = 12 * 1024 * 1024


class VehicleAngleRequest(BaseModel):
    originalImageBase64: str
    expectedAngle: str


ANGLE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "carPresent": {"type": "boolean"},
        "wholeVehicleVisible": {"type": "boolean"},
        "visibilityScore": {"type": "number", "minimum": 0, "maximum": 1},
        "detectedAngle": {"type": "string", "enum": ["Front", "Rear", "Left", "Right", "Unknown"]},
        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
        "isStraightEnough": {"type": "boolean"},
        "straightnessScore": {"type": "number", "minimum": 0, "maximum": 1},
        "perspectiveIssue": {"type": "string"},
        "sideFrontPosition": {"type": "string", "enum": ["left", "right", "unknown"]},
        "cameraSideDirection": {"type": "string", "enum": ["bonnet_on_image_left", "bonnet_on_image_right", "unknown"]},
        "originalBonnetPosition": {"type": "string", "enum": ["image_left", "image_right", "unknown"]},
        "mirrorBonnetPosition": {"type": "string", "enum": ["image_left", "image_right", "unknown"]},
        "mirrorCheckPasses": {"type": "boolean"},
        "frontCues": {"type": "string"},
        "rearCues": {"type": "string"},
        "frontIsOnImageLeft": {"type": "boolean"},
        "frontIsOnImageRight": {"type": "boolean"},
        "frontEndX": {"type": ["number", "null"]},
        "rearEndX": {"type": ["number", "null"]},
        "bonnetEndX": {"type": ["number", "null"]},
        "bootEndX": {"type": ["number", "null"]},
        "sideProfileScore": {"type": "number", "minimum": 0, "maximum": 1},
        "isThreeQuarterSideView": {"type": "boolean"},
        "nearEndSizePercent": {"type": "number"},
        "farEndSizePercent": {"type": "number"},
        "wheelsAppearSimilarSize": {"type": "boolean"},
        "cameraPerpendicularToSide": {"type": "boolean"},
        "reason": {"type": "string"},
    },
}
ANGLE_SCHEMA["required"] = list(ANGLE_SCHEMA["properties"].keys())


PROMPT = """
Objectively classify the single supplied vehicle photograph for an inspection
app. Report what the image actually shows even when it does not match the slot
the user intended to upload.

Front and Rear mean the corresponding vehicle face points toward the camera.
For a side profile, Left means the bonnet/nose is at IMAGE A's left edge and
Right means it is at IMAGE A's right edge. These are image-coordinate codes,
not the vehicle's physical left/right side. Use headlights, grille and bonnet
as front cues; use tail-lights, boot and rear bumper as rear cues. The mirrored
For non-side views, all side-position fields must be unknown/false/null.

Reject partial vehicles, unclear ends, and three-quarter views. A valid side
calibration image must show the complete vehicle and be close to perpendicular
to its side. Coordinates run from 0 at image-left to 100 at image-right. Keep
the reason and cue descriptions short and factual.
""".strip()


def _validated_data_url(encoded: str) -> str:
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, TypeError) as error:
        raise HTTPException(status_code=400, detail="An image was not valid base64 JPEG data.") from error
    if not raw or len(raw) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Each image must be between 1 byte and 12 MB.")
    if not raw.startswith(b"\xff\xd8\xff"):
        raise HTTPException(status_code=400, detail="Only JPEG vehicle images are accepted.")
    return f"data:image/jpeg;base64,{encoded}"


def _response_text(payload: dict) -> str:
    for output in payload.get("output", []):
        for content in output.get("content", []):
            if content.get("type") == "output_text" and isinstance(content.get("text"), str):
                return content["text"]
    raise HTTPException(status_code=502, detail="OpenAI returned no angle-classification output.")


@router.post("/validate-vehicle-angle")
def validate_vehicle_angle(request: VehicleAngleRequest) -> dict:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured on the backend.")

    allowed_angles = {"Front", "Rear", "Left", "Right", "Unknown"}
    expected_angle = request.expectedAngle if request.expectedAngle in allowed_angles else "Unknown"

    body = {
        "model": os.getenv("OPENAI_VEHICLE_ANGLE_MODEL", "gpt-4o"),
        "max_output_tokens": 1200,
        "input": [{
            "role": "user",
            "content": [
                {
                    "type": "input_text",
                    "text": (
                        f"{PROMPT}\n\nThe app is validating the {expected_angle} slot. "
                        "First classify the photo independently, then explain whether it matches that slot. "
                        "Do not change detectedAngle merely to agree with the expected slot."
                    ),
                },
                {"type": "input_image", "image_url": _validated_data_url(request.originalImageBase64), "detail": "high"},
            ],
        }],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "vehicle_angle_validation",
                "strict": True,
                "schema": ANGLE_SCHEMA,
            }
        },
    }

    openai_request = urllib.request.Request(
        OPENAI_RESPONSES_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(openai_request, timeout=30) as response:
            openai_payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        message = "OpenAI rejected the angle-validation request."
        try:
            details = json.loads(error.read())
            message = details.get("error", {}).get("message", message)
        except (json.JSONDecodeError, AttributeError):
            pass
        raise HTTPException(status_code=502, detail=message) from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise HTTPException(status_code=504, detail="Could not reach OpenAI for angle validation.") from error

    try:
        result = json.loads(_response_text(openai_payload))
    except json.JSONDecodeError as error:
        raise HTTPException(status_code=502, detail="OpenAI returned invalid structured output.") from error

    print(
        "[vehicle-angle]",
        f"expected={expected_angle}",
        f"detected={result.get('detectedAngle', 'Unknown')}",
        f"confidence={result.get('confidence', 0)}",
        f"reason={result.get('reason', '')}",
    )
    return result
