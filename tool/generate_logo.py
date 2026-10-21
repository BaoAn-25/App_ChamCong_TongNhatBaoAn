import os, math
from PIL import Image, ImageDraw, ImageFilter

def create_logo(size=1024):
    scale = 2
    S = size * scale  # 2048 for supersampling
    
    # Base image
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    
    # Outer rounded squircle
    pad = int(100 * scale)
    corner_radius = int(420 * scale)
    
    mask = Image.new('L', (S, S), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([pad, pad, S - pad, S - pad], radius=corner_radius, fill=255)
    
    # Vibrant modern gradient: from #00B4D8 (cyan) to #087F8C (brand teal) to #034047 (deep midnight teal)
    grad = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    for y in range(S):
        for x in range(S):
            # Diagonal gradient factor
            t = (x + y * 1.2) / (S * 2.2)
            t = max(0.0, min(1.0, t))
            
            # Start: (0, 180, 216) -> Mid: (8, 127, 140) -> End: (4, 52, 60)
            if t < 0.5:
                sub_t = t * 2.0
                r = int(0 * (1 - sub_t) + 8 * sub_t)
                g = int(180 * (1 - sub_t) + 127 * sub_t)
                b = int(216 * (1 - sub_t) + 140 * sub_t)
            else:
                sub_t = (t - 0.5) * 2.0
                r = int(8 * (1 - sub_t) + 4 * sub_t)
                g = int(127 * (1 - sub_t) + 52 * sub_t)
                b = int(140 * (1 - sub_t) + 60 * sub_t)
            grad.putpixel((x, y), (r, g, b, 255))
            
    canvas = Image.composite(grad, img, mask)
    draw = ImageDraw.Draw(canvas)
    
    # Inner subtle glossy border
    border_mask = Image.new('L', (S, S), 0)
    b_draw = ImageDraw.Draw(border_mask)
    b_draw.rounded_rectangle([pad, pad, S - pad, S - pad], radius=corner_radius, outline=255, width=int(8 * scale))
    white_border = Image.new('RGBA', (S, S), (255, 255, 255, 45))
    canvas.paste(white_border, (0, 0), border_mask)
    
    # Center coordinates
    cx, cy = S // 2, S // 2
    
    # Draw Clock Dial (Circular Track for Time / Attendance)
    dial_radius = int(480 * scale)
    track_width = int(54 * scale)
    
    # Outer glowing track
    draw.ellipse(
        [cx - dial_radius, cy - dial_radius, cx + dial_radius, cy + dial_radius],
        outline=(255, 255, 255, 70),
        width=track_width
    )
    
    # Clock hour tick marks (12, 3, 6, 9)
    tick_length = int(40 * scale)
    tick_w = int(22 * scale)
    for angle in [0, 90, 180, 270]:
        rad = math.radians(angle)
        r_outer = dial_radius - track_width // 2 - int(10 * scale)
        r_inner = r_outer - tick_length
        x1 = cx + int(r_inner * math.sin(rad))
        y1 = cy - int(r_inner * math.cos(rad))
        x2 = cx + int(r_outer * math.sin(rad))
        y2 = cy - int(r_outer * math.cos(rad))
        draw.line([x1, y1, x2, y2], fill=(255, 255, 255, 180), width=tick_w)
    
    # Stylized Clock Hands pointing to 9:00 (Nhóm 09)
    # Hour hand pointing Left (9 o'clock)
    h_len = int(220 * scale)
    h_w = int(44 * scale)
    draw.line([cx, cy, cx - h_len, cy], fill=(255, 255, 255, 240), width=h_w)
    
    # Minute hand pointing Up (12 o'clock)
    m_len = int(320 * scale)
    m_w = int(36 * scale)
    draw.line([cx, cy, cx, cy - m_len], fill=(255, 255, 255, 240), width=m_w)
    
    # Center Pin / Pivot
    pivot_r = int(55 * scale)
    draw.ellipse([cx - pivot_r, cy - pivot_r, cx + pivot_r, cy + pivot_r], fill=(255, 255, 255, 255))
    inner_pivot = int(24 * scale)
    draw.ellipse([cx - inner_pivot, cy - inner_pivot, cx + inner_pivot, cy + inner_pivot], fill=(8, 127, 140, 255))
    
    # Dynamic Bold Checkmark (Representing Attendance Success / Punctuality)
    # Checkmark coords in bottom-right quadrant
    chk_start = (cx + int(30 * scale), cy + int(120 * scale))
    chk_vertex = (cx + int(190 * scale), cy + int(290 * scale))
    chk_end = (cx + int(490 * scale), cy - int(50 * scale))
    chk_width = int(68 * scale)
    
    # Subtle drop shadow for checkmark
    shadow_offset = int(14 * scale)
    draw.line(
        [(chk_start[0], chk_start[1] + shadow_offset),
         (chk_vertex[0], chk_vertex[1] + shadow_offset),
         (chk_end[0], chk_end[1] + shadow_offset)],
        fill=(0, 40, 50, 100),
        width=chk_width + int(10 * scale),
        joint='curve'
    )
    
    # Vivid vibrant Emerald-to-White checkmark
    draw.line(
        [chk_start, chk_vertex, chk_end],
        fill=(52, 211, 153, 255), # Emerald Green #34D399
        width=chk_width,
        joint='curve'
    )
    # Checkmark rounded tips
    cap_r = chk_width // 2
    draw.ellipse([chk_start[0] - cap_r, chk_start[1] - cap_r, chk_start[0] + cap_r, chk_start[1] + cap_r], fill=(52, 211, 153, 255))
    draw.ellipse([chk_end[0] - cap_r, chk_end[1] - cap_r, chk_end[0] + cap_r, chk_end[1] + cap_r], fill=(52, 211, 153, 255))
    
    # Downscale with high quality Lanczos filter
    final_img = canvas.resize((size, size), Image.Resampling.LANCZOS)
    return final_img

if __name__ == '__main__':
    logo = create_logo(1024)
    os.makedirs('assets/images', exist_ok=True)
    logo.save('assets/images/app_logo.png')
    print('Saved assets/images/app_logo.png')
    
    # Resizing for Android mipmap launcher icons
    mipmaps = {
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    }
    for path, sz in mipmaps.items():
        resized = logo.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(path)
        print(f'Saved {path} ({sz}x{sz})')
