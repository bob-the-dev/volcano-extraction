# Navigation Setup Guide

## Baking the Navigation Mesh to Avoid Obstacles

Your click-to-move system is now set up, but you need to **bake the navigation mesh** in Godot to make it detect and avoid obstacles (walls, rocks, etc.).

### Steps to Bake Navigation Mesh:

1. **Open `main.tscn` in Godot**
2. **Select the `NavigationRegion3D` node** in the Scene tree

3. **In the Inspector panel**, find the `NavigationMesh` property and click on it to expand settings

4. **Key Settings** (already configured for you):
   - `Geometry > Parsed Geometry Type`: **Static Colliders** (detects StaticBody3D obstacles)
   - `Geometry > Collision Mask`: Layer 1 (default collision layer)
   - `Agent > Height`: 2.0 (your character's height)
   - `Agent > Radius`: 0.5 (character width for avoiding walls)
   - `Agent > Max Climb`: 0.5 (maximum step height)
   - `Agent > Max Slope`: 45° (steepest walkable slope)
   - `Filter > Low Hanging Obstacles`: Enabled
   - `Filter > Ledge Spans`: Enabled
   - `Filter > Walkable Low Height Spans`: Enabled

5. **Bake the NavMesh**:
   - With `NavigationRegion3D` selected
   - Look at the **top toolbar** of the 3D viewport
   - Click the **"Bake NavMesh"** button (looks like a puzzle piece icon)
   - Wait for the baking to complete

6. **Verify the Result**:
   - The navigation mesh should appear as a **blue transparent overlay** on walkable surfaces
   - Obstacles (walls, rocks) should have **gaps/holes** around them
   - If you don't see it, enable **Debug > Visible Navigation** in the editor

### Troubleshooting:

**If obstacles are not being avoided:**

- Check that wall/rock objects have `StaticBody3D` or `CollisionShape3D` (they do in WallPart.tscn)
- Verify the collision layer matches the `Geometry > Collision Mask` setting
- Adjust `Agent > Radius` to give more clearance around obstacles
- Rebake after any changes

**If navigation mesh is too small:**

- The current setup creates a mesh for a 100x100 area
- Your floor is 4000x4000, so you might need to add children or expand the region
- Consider adding `NavigationRegion3D` nodes for different areas

**If character gets stuck:**

- Increase `Path Desired Distance` and `Target Desired Distance` in the NavigationAgent3D
- Currently set to 0.5 units - try 1.0 or higher

### Testing:

1. Run the scene (F5)
2. **Left-click** anywhere on the ground
3. Character should walk to the clicked position
4. Character should **automatically avoid walls and rocks**

### Visual Debugging:

To see the path in real-time:

- Enable **Debug > Visible Navigation** in the Godot editor
- Or add this to your Player script's `_process()`:
  ```gdscript
  if navigation_agent.is_navigation_finished() == false:
      DebugDraw3D.draw_line_path(navigation_agent.get_current_navigation_path(), Color.GREEN)
  ```

## Current Setup:

✅ NavigationAgent3D added to Player  
✅ NavigationRegion3D added to Main scene  
✅ NavigationMesh configured for obstacle detection  
✅ Obstacles have collision shapes  
⏳ **Navigation mesh needs to be baked** (your action required)

After baking, the click-to-move system will intelligently navigate around all obstacles!
