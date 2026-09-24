import csv, math

rows = []

with open("imu_orientation.csv", newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)

    for r in reader:
        ax = float(r["accel_x"])
        ay = float(r["accel_y"])
        az = float(r["accel_z"])

        roll = math.radians(float(r["roll_deg"]))
        pitch = math.radians(float(r["pitch_deg"]))
        yaw = math.radians(float(r["yaw_deg"]))

        # Body -> world rotation
        cr, sr = math.cos(roll), math.sin(roll)
        cp, sp = math.cos(pitch), math.sin(pitch)
        cy, sy = math.cos(yaw), math.sin(yaw)

        wx = (
            (cy*cp)*ax
            + (cy*sp*sr - sy*cr)*ay
            + (cy*sp*cr + sy*sr)*az
        )

        wy = (
            (sy*cp)*ax
            + (sy*sp*sr + cy*cr)*ay
            + (sy*sp*cr - cy*sr)*az
        )

        wz = (
            (-sp)*ax
            + (cp*sr)*ay
            + (cp*cr)*az
        )

        # Remove gravity
        wx_linear = wx
        wy_linear = wy
        wz_linear = wz - 9.81

        r["world_accel_x"] = wx
        r["world_accel_y"] = wy
        r["world_accel_z"] = wz
        r["linear_world_x"] = wx_linear
        r["linear_world_y"] = wy_linear
        r["linear_world_z"] = wz_linear

        rows.append(r)

with open("imu_world_accel.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

print("DONE")
print("Samples:", len(rows))
print("Output: imu_world_accel.csv")
print("First world linear acceleration:")
print(rows[0]["linear_world_x"],
      rows[0]["linear_world_y"],
      rows[0]["linear_world_z"])
