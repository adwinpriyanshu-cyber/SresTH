import csv, math

INPUT = "imu_walking.csv"
OUTPUT = "step_dr.csv"

rows = []
with open(INPUT, newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

steps = 0
last_step = -999
step_length = 0.70

x = 0.0
y = 0.0

for i, r in enumerate(rows):
    ax = float(r["accel_x"])
    ay = float(r["accel_y"])
    az = float(r["accel_z"])

    mag = math.sqrt(ax*ax + ay*ay + az*az)

    if mag > 10.2 and i - last_step > 3:
        steps += 1
        last_step = i

    heading = 0.0
    if "gyro_z" in r:
        heading += float(r["gyro_z"])

    x = steps * step_length

    r["detected_steps"] = steps
    r["estimated_x_m"] = x
    r["estimated_y_m"] = y

with open(OUTPUT, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

print("DONE")
print("Samples:", len(rows))
print("Detected steps:", steps)
print("Estimated distance:", steps * step_length, "m")
print("Output:", OUTPUT)
