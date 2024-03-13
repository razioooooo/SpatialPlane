import UIKit
import QuartzCore
import SceneKit
import SwiftUI
import SwiftUIJoystick
import Combine
import PHASE

public struct Joystick: View {
    
    @ObservedObject public var joystickMonitor: JoystickMonitor
    
    private let dragDiameter: CGFloat
    private let shape: JoystickShape
    
    public init(monitor: JoystickMonitor, width: CGFloat, shape: JoystickShape = .circle) {
        self.joystickMonitor = monitor
        self.dragDiameter = width
        self.shape = shape
    }
    
    public var body: some View {
        VStack{
            JoystickBuilder(
                monitor: self.joystickMonitor,
                width: self.dragDiameter,
                shape: .circle,
                background: {
                    // Example Background
                    Circle().fill(Color.blue.opacity(0.9))
                        .frame(width: dragDiameter, height: dragDiameter)
                },
                foreground: {
                    // Example Thumb
                    Circle().fill(Color.black)
                        .frame(width: 20, height: 20)
                },
                locksInPlace: true)
        }
    }
}


class GameViewController: UIViewController {
    
    @ObservedObject var monitor = JoystickMonitor()
    
    var cancel: Any?
    
    // PHASE
    var engine: PHASEEngine!
    var listener: PHASEListener!
    var source: PHASESource!


    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 配置 PHASE 相关
        configEngine()
        
        // create a new scene
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        
        // create and add a camera to the scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 20
        scene.rootNode.addChildNode(cameraNode)
        
        // place the camera
        cameraNode.position = SCNVector3(x: 0, y: 15, z: 0)
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)


        // create and add a light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        scene.rootNode.addChildNode(lightNode)
        
        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        // retrieve the ship node
        let ship = scene.rootNode.childNode(withName: "ship", recursively: true)!
        
        // retrieve the SCNView
        let scnView = self.view as! SCNView
        
        // set the scene to the view
        scnView.scene = scene
        
        // allows the user to manipulate the camera
        scnView.allowsCameraControl = false
        
        // show statistics such as fps and timing information
        scnView.showsStatistics = true
        
        // configure the view
        scnView.backgroundColor = UIColor.black
        
        let joyStick = Joystick(monitor: monitor, width: 150, shape: .circle)
        let hostingController = UIHostingController(rootView: joyStick)
                
        view.addSubview(hostingController.view)
                
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 50),
            hostingController.view.widthAnchor.constraint(equalToConstant: 150),
            hostingController.view.heightAnchor.constraint(equalToConstant: 150)
        ])
                
        hostingController.didMove(toParent: self)
        
        cancel = monitor.objectWillChange.sink { _ in
            
            let x =  self.monitor.xyPoint.x / 10
            let z = self.monitor.xyPoint.y / 10
            
            print("x: \(x), y: \(z)")
            
            // 创建旋转矩阵
            
            // 计算从 p1 到 p2 的方向向量
            let p1 = ship.position
            let p2 = SCNVector3(x, 0, z)
            let directionVector =  SCNVector3(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z)

            // 计算旋转角度和轴
            let angle = atan2(directionVector.x, directionVector.z)
            let rotationAxis = SCNVector3(0, 1, 0)
            let rotationMatrix = SCNMatrix4MakeRotation(Float(angle), rotationAxis.x, rotationAxis.y, rotationAxis.z)
            
            // 创建平移矩阵
            let translationMatrix = SCNMatrix4MakeTranslation(Float(x), 0, Float(z))
            ship.transform = SCNMatrix4Mult(rotationMatrix, translationMatrix)
            
            // 关联音源 与 飞机的位置
            self.source.transform = simd_float4x4(translationMatrix)

        }
        
        // add a tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
    }
    
    func configEngine() {
        
        self.engine = PHASEEngine(updateMode: .automatic)
        self.engine.defaultReverbPreset = .largeRoom
        try? self.engine.start()

        // Listener
        self.listener = PHASEListener(engine: self.engine)
        // 设置收听者的位置
        self.listener.transform = matrix_identity_float4x4
        // 添加到场景中
        try? self.engine.rootObject.addChild(listener)
        
        // 设置播放源 Source
        // 播放源形状
        let mesh = MDLMesh.newIcosahedron(withRadius: 0.0142, inwardNormals: false, allocator:nil)
        let shape = PHASEShape(engine: engine, mesh: mesh)
        self.source = PHASESource(engine: engine, shapes: [shape])
        // 设置播放源位置，
        source.transform = matrix_identity_float4x4
        // 添加到场景中
        try? engine.rootObject.addChild(source)
        
        // 输出管道
        let pipeline = PHASESpatialPipeline(flags: [.directPathTransmission, .lateReverb])!
        pipeline.entries[PHASESpatialCategory.lateReverb]!.sendLevel = 0.1
        
        // 配置根据距离调节音量  
        // PHASEGeometricSpreadingDistanceModelParameters 模拟随距离的声音损失的模型
        let distanceModelParameters = PHASEGeometricSpreadingDistanceModelParameters()
        // 我们在控制了飞机在 15 米为半径的圆内飞行
        // 此处设置超过 16 米，超过 16 米声音渐隐
        distanceModelParameters.fadeOutParameters = PHASEDistanceModelFadeOutParameters(cullDistance: 16)
        distanceModelParameters.rolloffFactor = 0.3
        
        let spatialMixerDefinition = PHASESpatialMixerDefinition(spatialPipeline: pipeline)
        spatialMixerDefinition.distanceModelParameters = distanceModelParameters
        
        
        // 注册声音资源
        let soundURL = Bundle.main.url(forResource: "plane", withExtension: "mp3")!
        let soundAsset = try! self.engine.assetRegistry.registerSoundAsset(
            url: soundURL,
            identifier: "planeAsset",
            assetType: .resident,
            channelLayout: nil,
            normalizationMode: .dynamic)
        
        // 创建采样器节点
        let samplerNodeDefinition = PHASESamplerNodeDefinition(
            soundAssetIdentifier: soundAsset.identifier,
            mixerDefinition: spatialMixerDefinition
        )
        
        samplerNodeDefinition.playbackMode = .looping
        samplerNodeDefinition.setCalibrationMode(calibrationMode: .relativeSpl, level: 0)
        samplerNodeDefinition.cullOption = .sleepWakeAtRealtimeOffset
        
        // 向引擎注册声音事件节点的资产来提供有关声音事件事件信息
        let planeSoundEventAsset = try! engine.assetRegistry.registerSoundEventAsset(
            rootNode: samplerNodeDefinition,
            identifier: soundAsset.identifier + "_SoundEventAsset"
        )
        
        // 通过为每个空间混音器配置 PHASEMixerParameters 对象来定义播放音频的声源以及收听音频的听者
        let mixerParameters = PHASEMixerParameters()
        mixerParameters.addSpatialMixerParameters(
            identifier: spatialMixerDefinition.identifier,
            source: source,
            listener: listener
        )
        
        // 要播放声音，请为每个节点生成一个 PHASESoundEvent 实例，并在声音事件上调用 start(completion:)
        // 通过 PHASESoundEvent 初始化器 mixerParameters 参数传递空间混合器参数，将源与声音事件关联起来
        let planeSoundEvent = try! PHASESoundEvent(
            engine: engine,
            assetIdentifier: planeSoundEventAsset.identifier,
            mixerParameters: mixerParameters
        )

        planeSoundEvent.start()
        
    }
    
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        // retrieve the SCNView
        let scnView = self.view as! SCNView
        
        // check what nodes are tapped
        let p = gestureRecognize.location(in: scnView)
        let hitResults = scnView.hitTest(p, options: [:])
        // check that we clicked on at least one object
        if hitResults.count > 0 {
            // retrieved the first clicked object
            let result = hitResults[0]
            
            // get its material
            let material = result.node.geometry!.firstMaterial!
            
            // highlight it
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            
            // on completion - unhighlight
            SCNTransaction.completionBlock = {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                
                material.emission.contents = UIColor.black
                
                SCNTransaction.commit()
            }
            
            material.emission.contents = UIColor.red
            
            SCNTransaction.commit()
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

}
