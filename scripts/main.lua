function Start()
    -- 创建场景
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 创建相机
    local cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 0, -10)
    local camera = cameraNode:CreateComponent("Camera")

    -- 设置视口
    renderer:SetViewport(0, Viewport:new(scene_, camera))
end

function Stop()
end
