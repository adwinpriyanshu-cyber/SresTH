import csv
import math

INPUT = "imu_data.csv"
OUTPUT = "imu_processed.csv"

rows = []

with open(INPUT, "r", newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for r in reader:
        try:
            ax = float(r["accel_x"])
            ay = float(r["accel_y"])
            az = float(r["accel_z"])

            # Gravity magnitude
            acc_mag = math.sqrt(ax*ax + ay*ay + az*az)

            # Simple gravity estimate
            gx = 0.0
            gy = 0.0
            gz = 9.81

            # Gravity-removed acceleration
            lin_ax = ax - gx
            lin_ay = ay - gy
            lin_az = az - gz

            r["accel_magnitude"] = str(acc_mag)
            r["linear_accel_x"] = str(lin_ax)
            r["linear_accel_y"] = str(lin_ay)
            r["linear_accel_z"] = str(lin_az)

            rows.append(r)

        except (ValueError, KeyError):
            continue

if rows:
    fields = list(rows[0].keys())

    with open(OUTPUT, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

print("DONE")
print("Samples:", len(rows))
print("Output:", OUTPUT)
