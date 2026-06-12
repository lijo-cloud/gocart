// Example using Prisma (adjust based on your ORM/DB driver like pg, mongoose, etc.)
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

export const dynamic = 'force-dynamic'; // Crucial!

export async function GET() {
  try {
    // 1. Simulates a standard database read operation
    // Use a small lookup table to avoid overloading the DB completely on test 1
    const data = await prisma.product.findMany({ take: 5 }); 
    
    return Response.json({ status: "success", count: data.length }, { status: 200 });
  } catch (error) {
    console.error("DB Error:", error);
    return Response.json({ status: "error", message: error.message }, { status: 500 });
  }
}

export async function POST(request) {
  try {
    // 2. Simulates a database write operation (e.g., adding an item to a cart)
    const body = await request.json();
    
    const newRecord = await prisma.testLog.create({
      data: {
        payload: JSON.stringify(body),
        timestamp: new Date()
      }
    });

    return Response.json({ status: "created", id: newRecord.id }, { status: 201 });
  } catch (error) {
    return Response.json({ status: "error", message: error.message }, { status: 500 });
  }
}
