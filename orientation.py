import csv, math

rows = []

with open("imu_data.csv", newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for x in reader:
        ax = float(x["accel_x"])
        ay = float(x["accel_y"])
        az = float(x["accel_z"])
        mx = float(x["mag_x"])
        my = float(x["mag_y"])
        mz = float(x["mag_z"])

        roll = math.atan2(ay, az)
        pitch = math.atan2(-ax, math.sqrt(ay*ay + az*az))

        mx2 = mx * math.cos(pitch) + mz * math.sin(pitch)

        my2 = (
            mx * math.sin(roll) * math.sin(pitch)
            + my * math.cos(roll)
            - mz * math.sin(roll) * math.cos(pitch)
        )

        yaw = math.atan2(-my2, mx2)

        x["roll_deg"] = math.degrees(roll)
        x["pitch_deg"] = math.degrees(pitch)
        x["yaw_deg"] = math.degrees(yaw)

        rows.append(x)

with open("imu_orientation.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

print("DONE")
print("Samples:", len(rows))
print("Roll:", rows[0]["roll_deg"])
print("Pitch:", rows[0]["pitch_deg"])
print("Yaw:", rows[0]["yaw_deg"])
