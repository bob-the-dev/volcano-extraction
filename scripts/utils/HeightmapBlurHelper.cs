using System;
using Godot;

[GlobalClass]
public partial class HeightmapBlurHelper : RefCounted
{
    public Image BuildCollisionHeightmapImageRf(Image sourceImage, Image wallImage, int sampleWidth, int sampleDepth, float baseAmplitude, float wallAmplitude)
    {
        if (sourceImage == null)
        {
            return null;
        }

        if (sampleWidth <= 0 || sampleDepth <= 0)
        {
            return null;
        }

        int sourceWidth = sourceImage.GetWidth();
        int sourceHeight = sourceImage.GetHeight();
        if (sourceWidth <= 0 || sourceHeight <= 0)
        {
            return null;
        }

        float[] sourceValues = GetRfImageValues(sourceImage);
        if (sourceValues == null)
        {
            return null;
        }

        float[] wallValues = null;
        int wallWidth = 0;
        int wallHeight = 0;
        if (wallImage != null && wallAmplitude > 0.0f)
        {
            wallWidth = wallImage.GetWidth();
            wallHeight = wallImage.GetHeight();
            if (wallWidth > 0 && wallHeight > 0)
            {
                wallValues = GetRfImageValues(wallImage);
            }
        }

        float totalAmplitude = Mathf.Max(baseAmplitude + wallAmplitude, 0.0001f);
        float[] resultValues = new float[sampleWidth * sampleDepth];

        for (int zIndex = 0; zIndex < sampleDepth; zIndex++)
        {
            float zUv = 0.0f;
            if (sampleDepth > 1)
            {
                zUv = zIndex / (float)(sampleDepth - 1);
            }

            int rowOffset = zIndex * sampleWidth;
            for (int xIndex = 0; xIndex < sampleWidth; xIndex++)
            {
                float xUv = 0.0f;
                if (sampleWidth > 1)
                {
                    xUv = xIndex / (float)(sampleWidth - 1);
                }

                float baseHeight = SampleBilinearRf(sourceValues, sourceWidth, sourceHeight, xUv, zUv) * baseAmplitude;
                float wallHeightValue = 0.0f;
                if (wallValues != null && wallWidth > 0 && wallHeight > 0 && wallAmplitude > 0.0f)
                {
                    wallHeightValue = SampleBilinearRf(wallValues, wallWidth, wallHeight, xUv, zUv) * wallAmplitude;
                }

                float combinedHeight = (baseHeight + wallHeightValue) / totalAmplitude;
                resultValues[rowOffset + xIndex] = Mathf.Clamp(combinedHeight, 0.0f, 1.0f);
            }
        }

        return CreateRfImage(sampleWidth, sampleDepth, resultValues);
    }


    public Image ApplyWallHeightmapBlendRf(Image sourceImage, Godot.Collections.Array<Vector3> wallStampData, float baseRadiusPixels, float peakRadiusPixels, float peakOffsetPixels, float baseStrength, float peakStrength)
    {
        if (sourceImage == null)
        {
            return null;
        }

        if (wallStampData.Count == 0 || baseStrength <= 0.0f)
        {
            return sourceImage;
        }

        int width = sourceImage.GetWidth();
        int height = sourceImage.GetHeight();
        if (width <= 0 || height <= 0)
        {
            return sourceImage;
        }

        int pixelCount = width * height;
        int byteCount = pixelCount * sizeof(float);
        byte[] sourceBytes = sourceImage.GetData();
        if (sourceBytes.Length < byteCount)
        {
            GD.PushWarning("[HeightmapBlurHelper] Source image data was smaller than expected for FORMAT_RF.");
            return sourceImage;
        }

        float[] resultValues = new float[pixelCount];
        Buffer.BlockCopy(sourceBytes, 0, resultValues, 0, byteCount);

        for (int wallIndex = 0; wallIndex < wallStampData.Count; wallIndex++)
        {
            Vector3 wallStamp = wallStampData[wallIndex];
            float centerX = wallStamp.X;
            float centerY = wallStamp.Y;
            float heightVariationRatio = wallStamp.Z;
            if (heightVariationRatio <= 0.0f)
            {
                continue;
            }

            RaiseHeightmapRegion(resultValues, width, height, centerX, centerY, baseRadiusPixels, baseStrength * heightVariationRatio);
            RaiseHeightmapRegion(resultValues, width, height, centerX - peakOffsetPixels, centerY - peakOffsetPixels, peakRadiusPixels, peakStrength * heightVariationRatio);
            RaiseHeightmapRegion(resultValues, width, height, centerX + peakOffsetPixels, centerY - peakOffsetPixels, peakRadiusPixels, peakStrength * heightVariationRatio);
            RaiseHeightmapRegion(resultValues, width, height, centerX - peakOffsetPixels, centerY + peakOffsetPixels, peakRadiusPixels, peakStrength * heightVariationRatio);
            RaiseHeightmapRegion(resultValues, width, height, centerX + peakOffsetPixels, centerY + peakOffsetPixels, peakRadiusPixels, peakStrength * heightVariationRatio);
        }

        byte[] resultBytes = new byte[byteCount];
        Buffer.BlockCopy(resultValues, 0, resultBytes, 0, byteCount);
        return Image.CreateFromData(width, height, false, sourceImage.GetFormat(), resultBytes);
    }


    public Image ApplyDetailNoiseRf(Image sourceImage, FastNoiseLite noise, Rect2I terrainGridRect, int pixelsPerCell, float cellSize, int edgeMargin, float noiseStrength, float worldScale)
    {
        if (sourceImage == null || noise == null)
        {
            return null;
        }

        if (pixelsPerCell <= 0 || Mathf.IsZeroApprox(noiseStrength))
        {
            return sourceImage;
        }

        int width = sourceImage.GetWidth();
        int height = sourceImage.GetHeight();
        if (width <= 0 || height <= 0)
        {
            return sourceImage;
        }

        int pixelCount = width * height;
        int byteCount = pixelCount * sizeof(float);
        byte[] sourceBytes = sourceImage.GetData();
        if (sourceBytes.Length < byteCount)
        {
            GD.PushWarning("[HeightmapBlurHelper] Source image data was smaller than expected for FORMAT_RF.");
            return sourceImage;
        }

        float[] sourceValues = new float[pixelCount];
        Buffer.BlockCopy(sourceBytes, 0, sourceValues, 0, byteCount);

        float[] resultValues = new float[pixelCount];
        System.Array.Copy(sourceValues, resultValues, pixelCount);

        float edgeOffset = edgeMargin * cellSize;
        for (int y = 0; y < height; y++)
        {
            int rowOffset = y * width;
            float gridY = y / (float)pixelsPerCell;
            float worldZ = ((terrainGridRect.Position.Y + gridY + 0.5f) * cellSize) + edgeOffset;
            float sampleZ = (worldZ + 281.0f) * worldScale;

            for (int x = 0; x < width; x++)
            {
                float gridX = x / (float)pixelsPerCell;
                float worldX = ((terrainGridRect.Position.X + gridX + 0.5f) * cellSize) + edgeOffset;
                float sampleX = (worldX + 137.0f) * worldScale;
                float detailNoise = noise.GetNoise2D(sampleX, sampleZ) * noiseStrength;
                float displacedHeight = Mathf.Clamp(sourceValues[rowOffset + x] + detailNoise, 0.0f, 1.0f);
                resultValues[rowOffset + x] = displacedHeight;
            }
        }

        byte[] resultBytes = new byte[byteCount];
        Buffer.BlockCopy(resultValues, 0, resultBytes, 0, byteCount);
        return Image.CreateFromData(width, height, false, sourceImage.GetFormat(), resultBytes);
    }


    public Image ApplyGaussianBlurRf(Image sourceImage, int radius, Rect2I blurBounds)
    {
        if (sourceImage == null)
        {
            return null;
        }

        if (radius <= 0)
        {
            return sourceImage;
        }

        int width = sourceImage.GetWidth();
        int height = sourceImage.GetHeight();
        if (width <= 0 || height <= 0)
        {
            return sourceImage;
        }

        Rect2I effectiveBlurBounds = GetEffectiveBlurBounds(width, height, blurBounds);
        if (effectiveBlurBounds.Size.X <= 0 || effectiveBlurBounds.Size.Y <= 0)
        {
            return sourceImage;
        }

        int pixelCount = width * height;
        int byteCount = pixelCount * sizeof(float);
        byte[] sourceBytes = sourceImage.GetData();
        if (sourceBytes.Length < byteCount)
        {
            GD.PushWarning("[HeightmapBlurHelper] Source image data was smaller than expected for FORMAT_RF.");
            return sourceImage;
        }

        float[] sourceValues = new float[pixelCount];
        Buffer.BlockCopy(sourceBytes, 0, sourceValues, 0, byteCount);

        float[] horizontalValues = new float[pixelCount];
        System.Array.Copy(sourceValues, horizontalValues, pixelCount);

        float[] resultValues = new float[pixelCount];
        System.Array.Copy(sourceValues, resultValues, pixelCount);

        float[] kernel = BuildGaussianKernel(radius);
        int minX = effectiveBlurBounds.Position.X;
        int maxX = effectiveBlurBounds.End.X - 1;
        int minY = effectiveBlurBounds.Position.Y;
        int maxY = effectiveBlurBounds.End.Y - 1;

        for (int y = minY; y <= maxY; y++)
        {
            int rowOffset = y * width;
            for (int x = minX; x <= maxX; x++)
            {
                float sum = 0.0f;
                for (int kernelOffset = -radius; kernelOffset <= radius; kernelOffset++)
                {
                    int sampleX = Math.Clamp(x + kernelOffset, minX, maxX);
                    sum += sourceValues[rowOffset + sampleX] * kernel[kernelOffset + radius];
                }

                horizontalValues[rowOffset + x] = sum;
            }
        }

        for (int y = minY; y <= maxY; y++)
        {
            int rowOffset = y * width;
            for (int x = minX; x <= maxX; x++)
            {
                float sum = 0.0f;
                for (int kernelOffset = -radius; kernelOffset <= radius; kernelOffset++)
                {
                    int sampleY = Math.Clamp(y + kernelOffset, minY, maxY);
                    sum += horizontalValues[(sampleY * width) + x] * kernel[kernelOffset + radius];
                }

                resultValues[rowOffset + x] = sum;
            }
        }

        byte[] resultBytes = new byte[byteCount];
        Buffer.BlockCopy(resultValues, 0, resultBytes, 0, byteCount);
        return Image.CreateFromData(width, height, false, sourceImage.GetFormat(), resultBytes);
    }


    private static Rect2I GetEffectiveBlurBounds(int width, int height, Rect2I blurBounds)
    {
        Rect2I effectiveBlurBounds = blurBounds;
        if (effectiveBlurBounds.Size.X <= 0 || effectiveBlurBounds.Size.Y <= 0)
        {
            effectiveBlurBounds = new Rect2I(0, 0, width, height);
        }

        int minX = Math.Clamp(effectiveBlurBounds.Position.X, 0, width);
        int minY = Math.Clamp(effectiveBlurBounds.Position.Y, 0, height);
        int maxX = Math.Clamp(effectiveBlurBounds.End.X, minX, width);
        int maxY = Math.Clamp(effectiveBlurBounds.End.Y, minY, height);
        return new Rect2I(minX, minY, maxX - minX, maxY - minY);
    }


    private static Image CreateRfImage(int width, int height, float[] rfValues)
    {
        byte[] resultBytes = new byte[rfValues.Length * sizeof(float)];
        Buffer.BlockCopy(rfValues, 0, resultBytes, 0, resultBytes.Length);
        return Image.CreateFromData(width, height, false, Image.Format.Rf, resultBytes);
    }


    private static float[] GetRfImageValues(Image image)
    {
        if (image == null)
        {
            return null;
        }

        int width = image.GetWidth();
        int height = image.GetHeight();
        if (width <= 0 || height <= 0)
        {
            return null;
        }

        int pixelCount = width * height;
        int byteCount = pixelCount * sizeof(float);
        byte[] sourceBytes = image.GetData();
        if (sourceBytes.Length < byteCount)
        {
            GD.PushWarning("[HeightmapBlurHelper] Source image data was smaller than expected for FORMAT_RF.");
            return null;
        }

        float[] rfValues = new float[pixelCount];
        Buffer.BlockCopy(sourceBytes, 0, rfValues, 0, byteCount);
        return rfValues;
    }


    private static float SampleBilinearRf(float[] rfValues, int width, int height, float uvX, float uvY)
    {
        if (rfValues == null || width <= 0 || height <= 0)
        {
            return 0.0f;
        }

        float clampedUvX = Mathf.Clamp(uvX, 0.0f, 1.0f);
        float clampedUvY = Mathf.Clamp(uvY, 0.0f, 1.0f);
        float pixelX = clampedUvX * (width - 1);
        float pixelY = clampedUvY * (height - 1);
        int x0 = (int)MathF.Floor(pixelX);
        int y0 = (int)MathF.Floor(pixelY);
        int x1 = Math.Min(x0 + 1, width - 1);
        int y1 = Math.Min(y0 + 1, height - 1);
        float xLerp = pixelX - x0;
        float yLerp = pixelY - y0;

        float topLeft = rfValues[(y0 * width) + x0];
        float topRight = rfValues[(y0 * width) + x1];
        float bottomLeft = rfValues[(y1 * width) + x0];
        float bottomRight = rfValues[(y1 * width) + x1];
        float top = Mathf.Lerp(topLeft, topRight, xLerp);
        float bottom = Mathf.Lerp(bottomLeft, bottomRight, xLerp);
        return Mathf.Lerp(top, bottom, yLerp);
    }


    private static void RaiseHeightmapRegion(float[] heightValues, int width, int height, float centerX, float centerY, float radiusPixels, float strength)
    {
        if (radiusPixels <= 0.0f || strength <= 0.0f)
        {
            return;
        }

        float radiusSquared = radiusPixels * radiusPixels;
        int minX = Math.Max((int)MathF.Floor(centerX - radiusPixels), 0);
        int maxX = Math.Min((int)MathF.Ceiling(centerX + radiusPixels), width - 1);
        int minY = Math.Max((int)MathF.Floor(centerY - radiusPixels), 0);
        int maxY = Math.Min((int)MathF.Ceiling(centerY + radiusPixels), height - 1);

        for (int pixelY = minY; pixelY <= maxY; pixelY++)
        {
            int rowOffset = pixelY * width;
            for (int pixelX = minX; pixelX <= maxX; pixelX++)
            {
                float sampleDeltaX = (pixelX + 0.5f) - centerX;
                float sampleDeltaY = (pixelY + 0.5f) - centerY;
                float distanceSquared = (sampleDeltaX * sampleDeltaX) + (sampleDeltaY * sampleDeltaY);
                if (distanceSquared > radiusSquared)
                {
                    continue;
                }

                float normalizedDistance = MathF.Sqrt(distanceSquared) / radiusPixels;
                float raiseWeight = 1.0f - normalizedDistance;
                raiseWeight = raiseWeight * raiseWeight * (3.0f - (2.0f * raiseWeight));

                int pixelIndex = rowOffset + pixelX;
                float currentHeight = heightValues[pixelIndex];
                float raisedHeight = currentHeight + ((1.0f - currentHeight) * raiseWeight * strength);
                if (raisedHeight > currentHeight)
                {
                    heightValues[pixelIndex] = Mathf.Clamp(raisedHeight, 0.0f, 1.0f);
                }
            }
        }
    }


    private static float[] BuildGaussianKernel(int radius)
    {
        int kernelSize = (radius * 2) + 1;
        float[] kernel = new float[kernelSize];
        float kernelSum = 0.0f;
        float sigma = radius / 2.0f;
        if (Mathf.IsZeroApprox(sigma))
        {
            sigma = 1.0f;
        }

        for (int kernelIndex = -radius; kernelIndex <= radius; kernelIndex++)
        {
            float value = Mathf.Exp(-((kernelIndex * kernelIndex) / (2.0f * sigma * sigma)));
            kernel[kernelIndex + radius] = value;
            kernelSum += value;
        }

        if (Mathf.IsZeroApprox(kernelSum))
        {
            kernel[radius] = 1.0f;
            return kernel;
        }

        for (int kernelIndex = 0; kernelIndex < kernel.Length; kernelIndex++)
        {
            kernel[kernelIndex] /= kernelSum;
        }

        return kernel;
    }
}