import UIKit
import QuartzCore
import SceneKit
import SwiftUI
import SwiftUIJoystick
import Combine

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

    override func viewDidLoad() {
        super.viewDidLoad()
        
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
        
//        // animate the 3d object
//        ship.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 2, z: 0, duration: 1)))
        
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

        }
        
        // add a tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
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
