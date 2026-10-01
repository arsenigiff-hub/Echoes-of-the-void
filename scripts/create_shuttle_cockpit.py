# ==============================================================================
# BLENDER 3.x / 4.x SCRIPT: Space Shuttle Cockpit Console & UI Generator
# ==============================================================================
# Инструкция по запуску:
# 1. Откройте Blender.
# 2. Перейдите во вкладку "Scripting" (Скриптинг).
# 3. Нажмите "New" (Создать скрипт), вставьте этот код и нажмите кнопку Run (Run Script / Alt+P).
# 4. В сцене появится готовая 3D-консоль космического шаттла с экранами, кнопками и материалами!
# ==============================================================================

import bpy
import math

def clean_or_create_collection(name="ShuttleCockpit"):
    if name in bpy.data.collections:
        col = bpy.data.collections[name]
    else:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col

def create_material(name, color, metallic=0.0, roughness=0.5, emission_color=None, emission_strength=1.0):
    mat = bpy.data.materials.get(name)
    if not mat:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        
        if bsdf:
            # Base Color
            bsdf.inputs['Base Color'].default_value = color
            
            # Metallic & Roughness
            if 'Metallic' in bsdf.inputs:
                bsdf.inputs['Metallic'].default_value = metallic
            if 'Roughness' in bsdf.inputs:
                bsdf.inputs['Roughness'].default_value = roughness
                
            # Emission handling (Blender 3.x / 4.x compatibility)
            if emission_color:
                if 'Emission' in bsdf.inputs and bsdf.inputs['Emission'].type == 'RGBA':
                    bsdf.inputs['Emission'].default_value = emission_color
                elif 'Emission Color' in bsdf.inputs:
                    bsdf.inputs['Emission Color'].default_value = emission_color
                
                if 'Emission Strength' in bsdf.inputs:
                    bsdf.inputs['Emission Strength'].default_value = emission_strength
    return mat

def build_shuttle_console():
    col = clean_or_create_collection("ShuttleCockpit")
    
    # ---------------------------------------------------------
    # 1. Материалы
    # ---------------------------------------------------------
    mat_console = create_material("Mat_ConsoleDark", (0.08, 0.09, 0.11, 1.0), metallic=0.8, roughness=0.35)
    mat_bezel = create_material("Mat_ScreenBezel", (0.03, 0.04, 0.05, 1.0), metallic=0.9, roughness=0.2)
    mat_screen_pfd = create_material("Mat_Screen_PFD", (0.0, 0.05, 0.1, 1.0), emission_color=(0.0, 0.75, 1.0, 1.0), emission_strength=3.0)
    mat_screen_sys = create_material("Mat_Screen_SYS", (0.05, 0.08, 0.02, 1.0), emission_color=(0.2, 1.0, 0.3, 1.0), emission_strength=2.5)
    mat_screen_nav = create_material("Mat_Screen_NAV", (0.1, 0.03, 0.0, 1.0), emission_color=(1.0, 0.5, 0.0, 1.0), emission_strength=2.5)
    
    mat_btn_cyan = create_material("Mat_Btn_Cyan", (0.0, 0.5, 0.8, 1.0), emission_color=(0.0, 0.8, 1.0, 1.0), emission_strength=4.0)
    mat_btn_amber = create_material("Mat_Btn_Amber", (0.8, 0.4, 0.0, 1.0), emission_color=(1.0, 0.6, 0.0, 1.0), emission_strength=4.0)
    mat_btn_green = create_material("Mat_Btn_Green", (0.0, 0.7, 0.2, 1.0), emission_color=(0.1, 1.0, 0.3, 1.0), emission_strength=4.0)
    mat_switch_metal = create_material("Mat_SwitchMetal", (0.7, 0.75, 0.8, 1.0), metallic=0.95, roughness=0.15)

    # ---------------------------------------------------------
    # 2. Главная панель приборов (Dashboard Panel)
    # ---------------------------------------------------------
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    panel = bpy.context.active_object
    panel.name = "Console_MainPanel"
    panel.scale = (3.2, 1.4, 0.15)
    panel.rotation_euler = (math.radians(25), 0, 0)
    panel.data.materials.append(mat_console)
    col.objects.link(panel)
    bpy.context.scene.collection.objects.unlink(panel)
    
    # Нижная под-панель переключателей (Lower Control Bench)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.65, -0.4))
    bench = bpy.context.active_object
    bench.name = "Console_LowerBench"
    bench.scale = (3.2, 0.8, 0.12)
    bench.rotation_euler = (math.radians(60), 0, 0)
    bench.data.materials.append(mat_console)
    col.objects.link(bench)
    bpy.context.scene.collection.objects.unlink(bench)

    # ---------------------------------------------------------
    # 3. Экраны МФД (Multi-Function Displays)
    # ---------------------------------------------------------
    screens_config = [
        ("MFD_PrimaryFlightDisplay", -1.0, mat_screen_pfd),
        ("MFD_SystemsDisplay",        0.0, mat_screen_sys),
        ("MFD_NavRadarDisplay",       1.0, mat_screen_nav)
    ]
    
    for name, x_pos, screen_mat in screens_config:
        # Рамка экрана (Bezel)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, -0.05, 0.05))
        bezel = bpy.context.active_object
        bezel.name = f"{name}_Bezel"
        bezel.scale = (0.88, 0.04, 0.72)
        bezel.rotation_euler = (math.radians(25), 0, 0)
        bezel.data.materials.append(mat_bezel)
        col.objects.link(bezel)
        bpy.context.scene.collection.objects.unlink(bezel)
        
        # Дисплей (Display Plane)
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=(x_pos, -0.075, 0.05))
        disp = bpy.context.active_object
        disp.name = f"{name}_Screen"
        disp.scale = (0.8, 0.65, 1.0)
        disp.rotation_euler = (math.radians(115), 0, 0)
        disp.data.materials.append(screen_mat)
        col.objects.link(disp)
        bpy.context.scene.collection.objects.unlink(disp)
        
        # Кнопки софт-клавиш под экраном (Softkeys)
        for b in range(5):
            bx = x_pos - 0.3 + (b * 0.15)
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, -0.22, -0.28))
            skey = bpy.context.active_object
            skey.name = f"{name}_Softkey_{b+1}"
            skey.scale = (0.08, 0.03, 0.04)
            skey.rotation_euler = (math.radians(25), 0, 0)
            skey.data.materials.append(mat_bezel)
            col.objects.link(skey)
            bpy.context.scene.collection.objects.unlink(skey)

    # ---------------------------------------------------------
    # 4. Панель тумблеров и кнопок (Switches & Push Buttons)
    # ---------------------------------------------------------
    btn_mats = [mat_btn_cyan, mat_btn_amber, mat_btn_green]
    
    # Кнопки с подсветкой на нижней панели
    for row in range(2):
        for col_i in range(12):
            bx = -1.35 + (col_i * 0.24)
            by = -0.6 - (row * 0.18)
            bz = -0.32 - (row * 0.15)
            
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, by, bz))
            btn = bpy.context.active_object
            btn.name = f"Btn_Illuminated_{row}_{col_i}"
            btn.scale = (0.12, 0.06, 0.05)
            btn.rotation_euler = (math.radians(60), 0, 0)
            
            # Назначаем материал
            m = btn_mats[(row + col_i) % len(btn_mats)]
            btn.data.materials.append(m)
            
            col.objects.link(btn)
            bpy.context.scene.collection.objects.unlink(btn)

    # Металлические тумблеры (Toggle Switches)
    for t in range(8):
        tx = -1.2 + (t * 0.34)
        ty = -0.42
        tz = -0.20
        
        # Основание тумблера
        bpy.ops.mesh.primitive_cylinder_add(radius=0.03, depth=0.04, location=(tx, ty, tz))
        base = bpy.context.active_object
        base.rotation_euler = (math.radians(60), 0, 0)
        base.data.materials.append(mat_bezel)
        col.objects.link(base)
        bpy.context.scene.collection.objects.unlink(base)
        
        # Рычажок
        bpy.ops.mesh.primitive_cylinder_add(radius=0.012, depth=0.1, location=(tx, ty - 0.02, tz + 0.03))
        lever = bpy.context.active_object
        lever.name = f"ToggleSwitch_{t+1}"
        lever.rotation_euler = (math.radians(35 if t % 2 == 0 else 80), 0, 0)
        lever.data.materials.append(mat_switch_metal)
        col.objects.link(lever)
        bpy.context.scene.collection.objects.unlink(lever)

    # ---------------------------------------------------------
    # 5. Освещение кабины (Cockpit Ambient Point Light)
    # ---------------------------------------------------------
    bpy.ops.object.light_add(type='POINT', location=(0, -0.8, 0.5))
    light = bpy.context.active_object
    light.name = "Cockpit_AmbientLight"
    light.data.color = (0.2, 0.7, 1.0)
    light.data.energy = 15.0
    col.objects.link(light)
    bpy.context.scene.collection.objects.unlink(light)
    
    print(">>> Shuttle Cockpit Console generated successfully in collection 'ShuttleCockpit'!")

build_shuttle_console()
