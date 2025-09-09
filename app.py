import cv2
import serial
import time
import logging
import threading
import os
from dotenv import load_dotenv
from supabase import create_client, Client
import base64
from flask import Flask, render_template, jsonify, request
from datetime import datetime
import serial.tools.list_ports

# --- Configuration ---
load_dotenv()
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
ESP32_BAUD_RATE = int(os.getenv("ESP32_BAUD_RATE", 9600))
OCCUPANCY_THRESHOLD = int(os.getenv("OCCUPANCY_THRESHOLD", 300))
INCIDENT_CAPTURE_DIR = os.getenv("INCIDENT_CAPTURE_DIR", "incident_captures")

# --- Logging ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Parking Slots ---
PARKING_SLOTS_CAM1 = [(100, 80, 30, 60), (160, 80, 30, 60), (230, 80, 30, 60),
                      (310, 80, 30, 60), (380, 80, 30, 60), (100, 150, 30, 60),
                      (160, 150, 30, 60), (230, 150, 30, 60), (310, 150, 30, 60), (380, 150, 30, 60)]

PARKING_SLOTS_CAM2 = [(100, 80, 30, 60), (160, 80, 30, 60), (230, 80, 30, 60),
                      (310, 80, 30, 60), (380, 80, 30, 60), (100, 150, 30, 60),
                      (160, 150, 30, 60), (230, 150, 30, 60), (310, 150, 30, 60), (380, 150, 30, 60)]

# --- Globals ---
app = Flask(__name__)
supabase = None
serial_conn = None
data_lock = threading.Lock()

parking_status = {
    "total_slots": len(PARKING_SLOTS_CAM1) + len(PARKING_SLOTS_CAM2),
    "available_total": 0,
    "available_lane1": 0,
    "available_lane2": 0,
    "lane1_total": len(PARKING_SLOTS_CAM1),
    "lane2_total": len(PARKING_SLOTS_CAM2)
}
processed_frame_cam1 = None
processed_frame_cam2 = None
manual_lane_status = {"lane1": "E", "lane2": "E"}
last_slot_status = {}

# --- Functions ---
def find_esp32_serial_port():
    logging.info("Searching for ESP32 serial port...")
    ports = serial.tools.list_ports.comports()
    for p in ports:
        if 'USB' in p.description.upper() or 'CP210X' in p.description.upper() or 'USB' in p.device.upper():
            logging.info(f"Found potential ESP32 port: {p.device}")
            return p.device
    logging.warning("No ESP32 serial port found.")
    return None

def initialize_supabase(url, key):
    try:
        client = create_client(url, key)
        logging.info("Supabase initialized.")
        return client
    except Exception as e:
        logging.error(f"Supabase init failed: {e}")
        return None

def initialize_serial(port, baud_rate):
    if not port:
        return None
    try:
        ser = serial.Serial(port, baud_rate, timeout=1)
        time.sleep(2)
        logging.info(f"Serial connected at {port}")
        return ser
    except serial.SerialException as e:
        logging.error(f"Serial connection failed: {e}")
        return None

def is_slot_occupied(roi, threshold=OCCUPANCY_THRESHOLD):
    if roi is None or roi.size == 0:
        return False
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5,5), 0)
    thresh = cv2.adaptiveThreshold(blur, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                   cv2.THRESH_BINARY_INV, 11, 2)
    white = cv2.countNonZero(thresh)
    return white > threshold

def send_to_esp32(ser, data):
    if ser and ser.is_open:
        try:
            ser.write(data.encode('utf-8'))
        except serial.SerialException as e:
            logging.error(f"ESP32 send error: {e}")

def process_lane(cam, slots, lane_id, manual_status, camera_id, location_id): # เพิ่ม location_id
    occupied_count = 0
    slot_statuses = []
    display_frame = None

    ret, frame = cam.read()
    if ret:
        display_frame = frame.copy()
        for idx, slot in enumerate(slots):
            x, y, w, h = slot
            roi = frame[y:y+h, x:x+w]
            if manual_status == "F":
                occupied = True
            else:
                occupied = is_slot_occupied(roi)
            status = "F" if occupied else "E"
            slot_id = idx + 1 + (0 if lane_id == 1 else len(PARKING_SLOTS_CAM1))
            slot_statuses.append({"slot_id": slot_id, "status": status, "lane": lane_id, "camera_id": camera_id, "location_id": location_id}) # เพิ่ม location_id
            if occupied:
                occupied_count += 1
            color = (0,0,255) if occupied else (0,255,0)
            cv2.rectangle(display_frame, (x,y), (x+w,y+h), color, 2)
    return occupied_count, slot_statuses, display_frame

def save_and_upload_image(client, camera_id, frame):
    if not client or frame is None:
        return {"success": False, "message": "No client or frame"}
    try:
        os.makedirs(INCIDENT_CAPTURE_DIR, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{camera_id}_{timestamp}.jpg"
        filepath = os.path.join(INCIDENT_CAPTURE_DIR, filename)
        cv2.imwrite(filepath, frame)
        with open(filepath, 'rb') as f:
            client.storage.from_("parking_lot_images").upload(f"public/{filename}", f.read())
        image_url = client.storage.from_("parking_lot_images").get_public_url(f"public/{filename}")
        client.table("parking_lot").insert([{"image": image_url, "date": datetime.now().isoformat(), "camera_id": camera_id}]).execute()
        return {"success": True, "message": f"{camera_id} image uploaded."}
    except Exception as e:
        logging.error(f"Image upload error: {e}")
        return {"success": False, "message": str(e)}

def update_parking_overview(client, cam_data):
    if not client:
        return
    try:
        for data in cam_data:
            client.table("parking_overview").upsert(data, on_conflict="camera_id").execute()
    except Exception as e:
        logging.error(f"Update overview error: {e}")

# --- Background Worker ---
def background_worker():
    global supabase, serial_conn, processed_frame_cam1, processed_frame_cam2, parking_status, manual_lane_status, last_slot_status
    supabase = initialize_supabase(SUPABASE_URL, SUPABASE_KEY)
    serial_conn = initialize_serial(find_esp32_serial_port(), ESP32_BAUD_RATE)

    cam1 = cv2.VideoCapture(0)
    cam2 = cv2.VideoCapture(1)
    if not cam1.isOpened() or not cam2.isOpened():
        logging.critical("Camera failed to open.")
        return

    # กำหนด location_id สำหรับแต่ละกล้อง
    location_mapping = {
        "camA": 8,  # สมมติให้ camA อยู่ที่ location_id 8
        "camB": 8   # สมมติให้ camB อยู่ที่ location_id 8
    }

    while True:
        try:
            slot_statuses = []
            with data_lock:
                # ส่ง location_id ที่ถูกต้องของแต่ละกล้องไป
                occ_L1, statuses_L1, processed_frame_cam1 = process_lane(cam1, PARKING_SLOTS_CAM1, 1, manual_lane_status["lane1"], "camA", location_mapping["camA"])
                occ_L2, statuses_L2, processed_frame_cam2 = process_lane(cam2, PARKING_SLOTS_CAM2, 2, manual_lane_status["lane2"], "camB", location_mapping["camB"])
                slot_statuses.extend(statuses_L1)
                slot_statuses.extend(statuses_L2)

                parking_status["available_lane1"] = len(PARKING_SLOTS_CAM1) - occ_L1
                parking_status["available_lane2"] = len(PARKING_SLOTS_CAM2) - occ_L2
                parking_status["available_total"] = parking_status["available_lane1"] + parking_status["available_lane2"]

            # Capture image if slot status changes
            for slot in slot_statuses:
                slot_id = slot["slot_id"]
                current_status = slot["status"]
                if slot_id not in last_slot_status:
                    last_slot_status[slot_id] = current_status
                    continue
                if last_slot_status[slot_id] != current_status:
                    if slot["lane"] == 1:
                        save_and_upload_image(supabase, "camA", processed_frame_cam1)
                    else:
                        save_and_upload_image(supabase, "camB", processed_frame_cam2)
                    last_slot_status[slot_id] = current_status

            # Send to ESP32
            send_to_esp32(serial_conn, 'F\n' if occ_L1+occ_L2 == parking_status["total_slots"] else 'E\n')
            send_to_esp32(serial_conn, f'L1{"F" if occ_L1==len(PARKING_SLOTS_CAM1) else "E"}\n')
            send_to_esp32(serial_conn, f'L2{"F" if occ_L2==len(PARKING_SLOTS_CAM2) else "E"}\n')

            # Update Supabase
            overview_data = [
                {"camera_id":"camA", "total_slots":len(PARKING_SLOTS_CAM1), "occupied":occ_L1, "available":len(PARKING_SLOTS_CAM1)-occ_L1, "status":"F" if occ_L1==len(PARKING_SLOTS_CAM1) else "E", "location_id": location_mapping["camA"]},
                {"camera_id":"camB", "total_slots":len(PARKING_SLOTS_CAM2), "occupied":occ_L2, "available":len(PARKING_SLOTS_CAM2)-occ_L2, "status":"F" if occ_L2==len(PARKING_SLOTS_CAM2) else "E", "location_id": location_mapping["camB"]}
            ]
            update_parking_overview(supabase, overview_data)
            supabase.table("parking_slots_status").upsert(slot_statuses).execute()

            time.sleep(1)
        except Exception as e:
            logging.error(f"Worker error: {e}", exc_info=True)
            time.sleep(5)

# --- Flask Routes ---
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/get_frame_cam1')
def get_frame_cam1():
    with data_lock:
        if processed_frame_cam1 is not None:
            ret, buffer = cv2.imencode('.jpg', processed_frame_cam1)
            if ret:
                return jsonify({'image_data': base64.b64encode(buffer).decode('utf-8')})
    return jsonify({'image_data': ''})

@app.route('/get_frame_cam2')
def get_frame_cam2():
    with data_lock:
        if processed_frame_cam2 is not None:
            ret, buffer = cv2.imencode('.jpg', processed_frame_cam2)
            if ret:
                return jsonify({'image_data': base64.b64encode(buffer).decode('utf-8')})
    return jsonify({'image_data': ''})

@app.route('/parking_data')
def parking_data():
    with data_lock:
        data = parking_status.copy()
        data.update({"manual_lane1": manual_lane_status["lane1"], "manual_lane2": manual_lane_status["lane2"]})
        return jsonify(data)

@app.route('/set_lane_status/<int:lane_id>/<string:status>', methods=['POST'])
def set_lane_status(lane_id, status):
    with data_lock:
        if lane_id==1 and status in ["E","F"]:
            manual_lane_status["lane1"]=status
        elif lane_id==2 and status in ["E","F"]:
            manual_lane_status["lane2"]=status
        else:
            return jsonify({"success":False,"message":"Invalid"}),400
        return jsonify({"success":True,"message":f"Lane {lane_id} set to {status}"})

@app.route('/capture_images', methods=['POST'])
def capture_images():
    messages=[]
    with data_lock:
        if processed_frame_cam1 is not None:
            messages.append(save_and_upload_image(supabase,"camA",processed_frame_cam1)["message"])
        if processed_frame_cam2 is not None:
            messages.append(save_and_upload_image(supabase,"camB",processed_frame_cam2)["message"])
    return jsonify({"success":True,"messages":messages})

# --- Main ---
if __name__=="__main__":
    threading.Thread(target=background_worker, daemon=True).start()
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
