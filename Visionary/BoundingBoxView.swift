import UIKit

class BoundingBoxView: UIView {
    private var boundingBoxes: [CGRect] = []
    private var labels: [String] = []
    
    func updateBoundingBoxes(_ boxes: [CGRect], labels: [String]) {
        self.boundingBoxes = boxes
        self.labels = labels
        setNeedsDisplay()
    }

    func clear() {
        self.boundingBoxes = []
        self.labels = []
        setNeedsDisplay()
        print("Bounding boxes cleared")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.clear(rect)
        for (index, box) in boundingBoxes.enumerated() {
            drawBoundingBox(context: context, box: box, label: labels[index])
        }
    }
    
    private func drawBoundingBox(context: CGContext, box: CGRect, label: String) {
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(2.0)
        context.stroke(box)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.white
        ]
        let labelSize = label.size(withAttributes: attributes)
        let labelRect = CGRect(x: box.minX, y: box.minY - labelSize.height, width: labelSize.width + 4, height: labelSize.height)
        
        context.setFillColor(UIColor.green.cgColor)
        context.fill(labelRect)
        label.draw(in: labelRect.insetBy(dx: 2, dy: 0), withAttributes: attributes) // Center text in the label background
    }
}
