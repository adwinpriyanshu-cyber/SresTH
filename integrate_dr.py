import csv, math

rows = []

with open("imu_world_accel.csv", newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    vx = 0.0
    vy = 0.0
    x = 0.0
    y = 0.0
    prev_t = None

    for r in reader:
        t = float(r["timestamp"]) / 1000.0

        ax = float(r["linear_world_x"])
        ay = float(r["linear_world_y"])

        if prev_t is not None:
            dt = t - prev_t

            if 0 < dt < 1.0:
                vx += ax * dt
                vy += ay * dt

                x += vx * dt
                y += vy * dt

        r["velocity_x"] = vx
        r["velocity_y"] = vy
        r["position_x_m"] = x
        r["position_y_m"] = y

        rows.append(r)
        prev_t = t

with open("dead_reckoning_trajectory.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

print("DONE")
print("Samples:", len(rows))
print("Final X:", x, "m")
print("Final Y:", y, "m")
print("Distance from start:", math.sqrt(x*x + y*y), "m")
