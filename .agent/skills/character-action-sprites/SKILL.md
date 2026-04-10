---
name: character-action-sprites
description: |
  横版 2D/2.5D 角色基础动作序列帧生成技能。用户上传一张角色原画图，自动生成 6 个基础动作的 AI 视频并提取为精灵图集（sprite sheet）。
  Use when users need to (1) 生成角色动作序列帧, (2) 从角色图片生成动画精灵图, (3) 创建 2D 横版游戏角色动画, (4) 生成 idle/walk/run/attack/jump 动作帧, (5) character action sprites, (6) 用户提供了角色图片并希望生成动作动画。
---

# 横版 2D 角色动作序列帧生成

从一张角色原画生成 6 个基础动作的序列帧精灵图集。

## 前置条件

- 用户提供一张角色原画图（全身、侧面或3/4视角优先）
- 图片格式: jpeg/png/webp，每边 300-6000px，宽高比 0.4-2.5

## 背景模式选择

生成视频前**必须询问用户**选择背景模式:

| 模式 | 背景描述 | 适用场景 |
|------|---------|---------|
| **绿幕** (推荐) | 纯绿色 #00FF00 | 后期抠图、合成到任意背景 |
| **纯白** | 纯白色 #FFFFFF | 直接使用、简洁风格 |

**Prompt 背景模板**:
- 绿幕: `"on a pure bright green chroma key background (#00FF00). The entire background must be flat solid green with no gradients, shadows, or reflections. Green screen studio setup."`
- 纯白: `"on a pure white background (#FFFFFF). The entire background must be flat solid white with no gradients, shadows, or reflections. White studio setup."`

将选中的背景描述替换掉各动作 prompt 中的 `"Clean solid color background."` 部分。

## 完整工作流

### Phase 1: 资产准备

1. 将用户图片复制到 `assets/image/` 目录
2. 调用 `upload_asset` 上传为受信资产，获得 `asset_uri`（格式 `asset://<id>`）
3. 记录 `asset_uri`，后续所有视频任务都使用它

### Phase 2: 逐个生成 6 个动作视频

**并发限制: 一次只能运行 1 个视频任务！必须等上一个完成再创建下一个。**

按以下顺序依次生成（每个用 `create_video_task` + `query_video_task`）:

#### 动作 1: Idle（待机）
```
mode: multi_modal_reference
images: [{ url: <asset_uri> }]
ratio: 1:1
duration: 4
prompt: "2D side-scrolling game character animation, pure side view facing right. Full body visible from head to feet, centered in frame. The fantasy armored character stands in idle pose, with subtle breathing motion - chest rises and falls gently, weight shifts slightly between feet, cape or cloth sways softly. Clean solid color background. Pixel-perfect loop-ready animation, consistent character proportions throughout."
```

#### 动作 2: Walk（行走）
```
mode: multi_modal_reference
images: [{ url: <asset_uri> }]
ratio: 16:9
duration: 5
prompt: "2D side-scrolling game character animation, pure side view. Full body visible from head to feet. The fantasy armored character walks steadily to the right, natural walking cycle with arms swinging opposite to legs, body bobbing slightly with each step, cape flowing with movement. Clean solid color background. Smooth walk cycle animation, consistent character design and proportions."
```

#### 动作 3: Run（奔跑）
```
mode: multi_modal_reference
images: [{ url: <asset_uri> }]
ratio: 16:9
duration: 5
prompt: "2D side-scrolling game character animation, pure side view. Full body visible from head to feet. The fantasy armored character runs energetically to the right, dynamic running cycle with exaggerated arm pumping, legs stretching wide, body leaning forward, hair and cape streaming behind. Clean solid color background. Dynamic fast-paced run cycle, consistent character design."
```

#### 动作 4: Normal Attack A（普通攻击）
```
mode: multi_modal_reference
images: [{ url: <asset_uri> }]
ratio: 16:9
duration: 4
prompt: "2D side-scrolling game character animation, pure side view facing right. Full body visible from head to feet. The fantasy armored character performs a quick forward strike - starts from ready stance, swings arm forward in a fast arc, body twists with the motion, then recovers to stance. Clean solid color background. Snappy attack animation with clear anticipation, strike, and recovery phases."
```

#### 动作 5: Heavy Attack B（重攻击）
```
mode: multi_modal_reference
images: [{ url: <asset_uri> }]
ratio: 16:9
duration: 6
prompt: "2D side-scrolling game character animation, pure side view facing right. Full body visible from head to feet. The fantasy armored character performs a powerful heavy strike - winds up with exaggerated back motion, pauses briefly, then unleashes a massive forward swing with full body rotation, strong follow-through. Clean solid color background. Dramatic heavy attack with clear windup, impact, and recovery."
```

#### 动作 6: Jump（跳跃）
```
mode: multi_modal_reference
images: [{ url: <asset_uri> }]
ratio: 9:16
duration: 5
prompt: "2D side-scrolling game character animation, pure side view facing right. Full body visible from head to feet. The fantasy armored character performs a jump sequence - crouches down preparing, launches upward with arms raised, reaches peak height with body stretched, then descends and lands with bent knees absorbing impact. Clean solid color background. Complete jump arc from ground to air and back to ground."
```

### Phase 3: 下载视频

每个视频任务完成后（status=SUCCESS），将视频文件记录路径。视频会自动保存到 `workspace_video_path`。

### Phase 4: 提取帧并生成精灵图集

所有 6 个视频就绪后，创建配置 JSON 并运行提取脚本:

```bash
# 1. 创建配置文件
cat > /tmp/sprite_config.json << 'EOF'
{
  "videos": {
    "idle":          "<idle视频路径>",
    "walk":          "<walk视频路径>",
    "run":           "<run视频路径>",
    "normal_attack": "<normal_attack视频路径>",
    "heavy_attack":  "<heavy_attack视频路径>",
    "jump":          "<jump视频路径>"
  },
  "output_dir": "/workspace/assets/spritesheets",
  "character_name": "<角色名>",
  "fps": 4,
  "frame_width": 1080,
  "frame_height": 1080
}
EOF

# 2. 安装依赖
pip install Pillow -q

# 3. 运行提取
python3 <skill_dir>/scripts/extract_spritesheet.py /tmp/sprite_config.json
```

### Phase 5: 产出汇总

生成完成后向用户报告:
- 每个动作的精灵图集文件路径和帧数
- `atlas_info.json` 位置及内容
- 帧规格（宽x高、列数x行数、总帧数、FPS）

## 内容安全提示词规则

视频生成可能被内容安全过滤器拦截。遵循以下规则:

1. **禁止使用**: sword, blade, weapon, blood, kill, slash, stab, cut, impale
2. **替代用语**: 用 "strike", "swing", "forward motion", "arm arc" 替代武器动作描述
3. **角色描述**: 用 "fantasy armored character" 而非具体武器描述
4. **如被拦截**: 进一步软化提示词，移除所有暴力暗示，重试

## 视频任务轮询规则

- 创建任务后至少等 **120 秒** 再首次查询
- 查询间隔不少于 120 秒
- 任务超时上限约 10 分钟
- 如果失败（FAILED），调整 prompt 后重试

## 参数调节指南

| 参数 | 默认值 | 说明 |
|------|--------|------|
| fps | 4 | 每秒提取帧数，4fps × 5s = 20帧（适中） |
| frame_width | 1080 | 单帧宽度（像素） |
| frame_height | 1080 | 单帧高度（像素） |
| duration | 4-6 | 视频时长秒数，动作越复杂越长 |

## 帧质量硬性规则

1. **单帧分辨率不低于 1080x1080**，确保不糊。视频源为 720p 时通过 ffmpeg lanczos 上采样。
2. **FPS 默认 4**，每个动作约 16-24 帧，平衡流畅度和图集体积。
3. **背景必须纯净统一**（绿幕或纯白），不允许渐变、阴影、倒影。
4. 绿幕转白底后**必须验证零绿色残留**。
