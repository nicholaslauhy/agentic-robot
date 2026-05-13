//
//  ShakeEffect.swift
//  agentic robot
//
//  Created by q2 on 13/5/26.
//

import SwiftUI

struct ShakeEffect: GeometryEffect {

    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {

        ProjectionTransform(
            CGAffineTransform(
                translationX:
                    amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
                y: 0
            )
        )
    }
}
